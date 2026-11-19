// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IAgentIdRegistry} from "./interfaces/IAgentIdRegistry.sol";

/// @title AgentKudos - tip any opted-in .ai Agent ID by name
/// @notice Non-custodial: every tip is forwarded to the recipient's Agent ID owner address in the
/// same transaction. This contract never holds user funds, has no owner, no admin, no fee,
/// no pause and no upgrade path. All configuration is immutable and set in the constructor.
/// @dev Recipients must opt in with `openJar()` from the wallet that owns their Agent ID, so the
/// contract cannot be used to pay (or look up) Agent IDs whose owners did not ask for it.
contract AgentKudos is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Native coin is represented as address(0) in events and totals.
    address public constant NATIVE = address(0);
    uint256 public constant MAX_MESSAGE_BYTES = 280;
    uint256 public constant MAX_BIO_BYTES = 160;

    IAgentIdRegistry public immutable registry;
    /// @notice ERC20 tokens accepted for tips (fixed at deployment; e.g. USDT, USDC on BSC).
    address public immutable tokenA;
    address public immutable tokenB;

    struct Jar {
        bool open;
        address owner; // Agent ID owner at the time the jar was opened (Agent IDs are soulbound)
        uint64 openedAt;
        uint32 tipsReceived;
        string bio;
    }

    /// @notice labelhash (keccak256 of the handle without ".ai") => jar
    mapping(bytes32 => Jar) internal _jars;
    /// @notice labelhash => token => total received
    mapping(bytes32 => mapping(address => uint256)) public received;
    /// @notice tipper => token => total sent
    mapping(address => mapping(address => uint256)) public sent;
    /// @notice tipper => number of tips sent
    mapping(address => uint32) public tipsSent;
    /// @notice tipper => number of distinct jars tipped
    mapping(address => uint32) public uniqueRecipients;
    mapping(address => mapping(bytes32 => bool)) internal _hasTipped;

    uint256 public totalTips;
    uint256 public totalJars;

    /// @notice Enumerable lists for on-chain leaderboards (no indexer needed).
    bytes32[] public jarLabels;
    mapping(bytes32 => string) public handleOfLabel;
    address[] public tippers;

    struct JarView {
        string handle;
        bool open;
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

    event JarOpened(bytes32 indexed labelhash, address indexed owner, string handle, string bio);
    event JarUpdated(bytes32 indexed labelhash, string bio);
    event JarClosed(bytes32 indexed labelhash);
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
    error JarNotOpen();
    error JarAlreadyOpen();
    error SelfTip();
    error ZeroAmount();
    error TokenNotAccepted();
    error MessageTooLong();
    error BioTooLong();
    error ForwardFailed();
    error StaleJar();

    constructor(IAgentIdRegistry registry_, address tokenA_, address tokenB_) {
        registry = registry_;
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    // ---------------------------------------------------------------- recipients

    /// @notice Opt in to receive tips at your .ai name. Caller must own an Agent ID.
    function openJar(string calldata bio) external {
        if (bytes(bio).length > MAX_BIO_BYTES) revert BioTooLong();
        string memory handle = registry.handleOf(msg.sender);
        if (bytes(handle).length == 0) revert NoAgentId();
        bytes32 label = keccak256(bytes(handle));
        Jar storage j = _jars[label];
        if (j.open) revert JarAlreadyOpen();
        if (j.openedAt == 0) {
            totalJars++;
            jarLabels.push(label);
            handleOfLabel[label] = handle;
        }
        j.open = true;
        j.owner = msg.sender;
        j.openedAt = uint64(block.timestamp);
        j.bio = bio;
        emit JarOpened(label, msg.sender, handle, bio);
    }

    function updateBio(string calldata bio) external {
        if (bytes(bio).length > MAX_BIO_BYTES) revert BioTooLong();
        bytes32 label = _ownLabel();
        _jars[label].bio = bio;
        emit JarUpdated(label, bio);
    }

    /// @notice Stop receiving tips. History and totals are kept.
    function closeJar() external {
        bytes32 label = _ownLabel();
        _jars[label].open = false;
        emit JarClosed(label);
    }

    // ---------------------------------------------------------------- tipping

    /// @notice Tip native BNB-chain coin to `handle` (without ".ai"). Forwarded immediately.
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

    function jarOf(string calldata handle)
        external
        view
        returns (bool open, uint64 openedAt, uint32 tipsReceived, string memory bio)
    {
        Jar storage j = _jars[keccak256(bytes(handle))];
        // A jar is only live while its opener still owns the handle (always true for soulbound IDs).
        bool live = j.open && registry.ownerOfHandle(handle) == j.owner;
        return (live, j.openedAt, j.tipsReceived, j.bio);
    }

    function tipperCount() external view returns (uint256) {
        return tippers.length;
    }

    /// @notice Paginated jar stats for leaderboards.
    function getJars(uint256 start, uint256 count) external view returns (JarView[] memory out) {
        uint256 n = jarLabels.length;
        if (start >= n) return out;
        if (count > n - start) count = n - start;
        out = new JarView[](count);
        for (uint256 i; i < count; ++i) {
            bytes32 l = jarLabels[start + i];
            Jar storage j = _jars[l];
            out[i] = JarView(
                handleOfLabel[l], j.open, j.tipsReceived, received[l][NATIVE], received[l][tokenA], received[l][tokenB]
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

    function _ownLabel() internal view returns (bytes32 label) {
        string memory handle = registry.handleOf(msg.sender);
        if (bytes(handle).length == 0) revert NoAgentId();
        label = keccak256(bytes(handle));
        Jar storage j = _jars[label];
        if (!j.open || j.owner != msg.sender) revert JarNotOpen();
    }

    function _prepare(string calldata handle, string calldata message) internal view returns (bytes32 label, address to) {
        if (bytes(message).length > MAX_MESSAGE_BYTES) revert MessageTooLong();
        label = keccak256(bytes(handle));
        Jar storage j = _jars[label];
        if (!j.open) revert JarNotOpen();
        to = registry.ownerOfHandle(handle); // resolved on-chain at tip time
        if (to == address(0) || to != j.owner) revert StaleJar();
        if (to == msg.sender) revert SelfTip();
    }

    function _record(bytes32 label, address to, address token, uint256 amount, string calldata handle, string calldata message)
        internal
    {
        Jar storage j = _jars[label];
        if (tipsSent[msg.sender] == 0) tippers.push(msg.sender);
        unchecked {
            j.tipsReceived++;
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
