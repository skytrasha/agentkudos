// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAgentIdRegistry} from "./interfaces/IAgentIdRegistry.sol";

/// @title AgentKudos - tip any .ai Agent ID by name
/// @notice Non-custodial: every tip is forwarded to the wallet that owns the Agent ID in the same
/// transaction. This contract never holds user funds, has no owner, no admin, no fee, no pause and
/// no upgrade path. All configuration is immutable and set in the constructor.
/// @dev Any registered handle can receive tips. An optional public bio can be set by the handle owner.
contract AgentKudos is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Native coin is represented as address(0) in events and totals.
    address public constant NATIVE = address(0);
    uint256 public constant MAX_MESSAGE_BYTES = 280;
    uint256 public constant MAX_BIO_BYTES = 160;

    IAgentIdRegistry public immutable registry;
    /// @notice ERC20 tokens accepted for tips (fixed at deployment; USDT and USDC on BSC).
    address public immutable tokenA;
    address public immutable tokenB;

    /// @notice labelhash (keccak256 of the handle without ".ai") => optional bio
    mapping(bytes32 => string) public bioOf;
    /// @notice labelhash => number of tips received
    mapping(bytes32 => uint32) public tipsReceived;
    /// @notice labelhash => token => total received
    mapping(bytes32 => mapping(address => uint256)) public received;
    /// @notice tipper => token => total sent
    mapping(address => mapping(address => uint256)) public sent;
    /// @notice tipper => number of tips sent
    mapping(address => uint32) public tipsSent;
    /// @notice tipper => number of distinct names tipped
    mapping(address => uint32) public uniqueRecipients;
    mapping(address => mapping(bytes32 => bool)) internal _hasTipped;

    uint256 public totalTips;

    /// @notice Enumerable lists for on-chain leaderboards (no indexer needed).
    bytes32[] public recipientLabels; // names that received at least one tip
    mapping(bytes32 => string) public handleOfLabel;
    address[] public tippers;

    struct RecipientView {
        string handle;
        uint32 tipsReceived;
        uint256 receivedNative;
        uint256 receivedTokenA;
        uint256 receivedTokenB;
    }

    struct TipperView {
        address tipper;
        string handle;
        uint32 tipsSent;
        uint32 uniqueRecipients;
        uint256 sentNative;
        uint256 sentTokenA;
        uint256 sentTokenB;
    }

    event BioSet(bytes32 indexed labelhash, string handle, string bio);
    /// @param fromHandle tipper's own Agent ID handle ("" if the tipper holds none)
    event Tipped(
        bytes32 indexed labelhash,
        address indexed from,
        address indexed token,
        address to,
        uint256 amount,
        string toHandle,
        string fromHandle,
        string message
    );

    error NoAgentId();
    error UnknownHandle();
    error SelfTip();
    error ZeroAmount();
    error TokenNotAccepted();
    error MessageTooLong();
    error BioTooLong();
    error ForwardFailed();

    constructor(IAgentIdRegistry registry_, address tokenA_, address tokenB_) {
        registry = registry_;
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    // ---------------------------------------------------------------- optional profile

    /// @notice Optional: set a public bio shown on your tip page. Caller must own an Agent ID.
    /// Not required to receive tips. Pass "" to clear it.
    function setBio(string calldata bio) external {
        if (bytes(bio).length > MAX_BIO_BYTES) revert BioTooLong();
        string memory handle = registry.handleOf(msg.sender);
        if (bytes(handle).length == 0) revert NoAgentId();
        bytes32 label = keccak256(bytes(handle));
        bioOf[label] = bio;
        emit BioSet(label, handle, bio);
    }

    // ---------------------------------------------------------------- tipping

    /// @notice Tip native coin to `handle` (without ".ai"). Forwarded immediately to its owner.
    function tip(string calldata handle, string calldata message) external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        (bytes32 label, address to) = _prepare(handle, message);
        _record(label, to, NATIVE, msg.value, handle, message);
        (bool ok,) = payable(to).call{value: msg.value}("");
        if (!ok) revert ForwardFailed();
    }

    /// @notice Tip an accepted ERC20. Caller approves exactly `amount` to this contract first;
    /// tokens move straight from the caller to the recipient via transferFrom.
    function tipToken(string calldata handle, address token, uint256 amount, string calldata message)
        external
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (token == address(0) || (token != tokenA && token != tokenB)) revert TokenNotAccepted();
        (bytes32 label, address to) = _prepare(handle, message);
        _record(label, to, token, amount, handle, message);
        IERC20(token).safeTransferFrom(msg.sender, to, amount);
    }

    // ---------------------------------------------------------------- views

    /// @notice Public tip-page info for a name. Deliberately does not return the owner address.
    function profileOf(string calldata handle)
        external
        view
        returns (bool registered, uint32 tips, string memory bio)
    {
        bytes32 label = keccak256(bytes(handle));
        return (registry.ownerOfHandle(handle) != address(0), tipsReceived[label], bioOf[label]);
    }

    function recipientCount() external view returns (uint256) {
        return recipientLabels.length;
    }

    function tipperCount() external view returns (uint256) {
        return tippers.length;
    }

    /// @notice Paginated recipient stats for leaderboards.
    function getRecipients(uint256 start, uint256 count) external view returns (RecipientView[] memory out) {
        uint256 n = recipientLabels.length;
        if (start >= n) return out;
        if (count > n - start) count = n - start;
        out = new RecipientView[](count);
        for (uint256 i; i < count; ++i) {
            bytes32 l = recipientLabels[start + i];
            out[i] = RecipientView(
                handleOfLabel[l], tipsReceived[l], received[l][NATIVE], received[l][tokenA], received[l][tokenB]
            );
        }
    }

    /// @notice Paginated tipper stats for leaderboards. `handle` is "" for non-holders.
    function getTippers(uint256 start, uint256 count) external view returns (TipperView[] memory out) {
        uint256 n = tippers.length;
        if (start >= n) return out;
        if (count > n - start) count = n - start;
        out = new TipperView[](count);
        for (uint256 i; i < count; ++i) {
            address t = tippers[start + i];
            out[i] = TipperView(
                t, registry.handleOf(t), tipsSent[t], uniqueRecipients[t], sent[t][NATIVE], sent[t][tokenA], sent[t][tokenB]
            );
        }
    }

    function isAgentIdHolder(address account) external view returns (bool) {
        return registry.balanceOf(account) > 0;
    }

    // ---------------------------------------------------------------- internal

    function _prepare(string calldata handle, string calldata message) internal view returns (bytes32 label, address to) {
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong();
        label = keccak256(bytes(handle));
        to = registry.ownerOfHandle(handle); // resolved on-chain at tip time
        if (to == address(0)) revert UnknownHandle();
        if (to == msg.sender) revert SelfTip();
    }

    function _record(bytes32 label, address to, address token, uint256 amount, string calldata handle, string calldata message)
        internal
    {
        if (tipsReceived[label] == 0) {
            recipientLabels.push(label);
            handleOfLabel[label] = handle;
        }
        if (tipsSent[msg.sender] == 0) tippers.push(msg.sender);
        unchecked {
            tipsReceived[label]++;
            tipsSent[msg.sender]++;
            totalTips++;
        }
        received[label][token] += amount;
        sent[msg.sender][token] += amount;
        if (!_hasTipped[msg.sender][label]) {
            _hasTipped[msg.sender][label] = true;
            unchecked {
                uniqueRecipients[msg.sender]++;
            }
        }
        emit Tipped(label, msg.sender, token, to, amount, handle, registry.handleOf(msg.sender), message);
    }
}
