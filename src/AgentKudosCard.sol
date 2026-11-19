// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAgentIdRegistry} from "./interfaces/IAgentIdRegistry.sol";
import {IAgentKudosStats} from "./interfaces/IAgentKudosStats.sol";

/// @title AgentKudosCard - free soulbound Kudos Card + daily gm for .ai Agent ID holders
/// @notice One non-transferable card per Agent ID (tokenId = registry tokenId = uint256(keccak256(handle))).
/// The card art is fully on-chain SVG and shows the holder's name, gm streak and kudos stats.
/// No owner, no admin, no fees, no payable functions, holds no funds, not upgradeable.
contract AgentKudosCard is ERC721 {
    using Strings for uint256;

    IAgentIdRegistry public immutable registry;
    IAgentKudosStats public immutable kudos;

    struct Gm {
        uint32 lastDay; // UTC day number (block.timestamp / 1 days) of the last gm, 0 = never
        uint32 streak; // consecutive days up to lastDay
        uint32 best; // best streak ever
        uint32 total; // total gm check-ins
        uint32 shoutsSent; // gm shout-outs sent to other names
        uint32 shoutsReceived; // gm shout-outs received
    }

    /// @notice labelhash => gm stats
    mapping(bytes32 => Gm) public gmOf;
    /// @notice labelhash => handle (stored the first time a name mints or says gm)
    mapping(bytes32 => string) public handleOfLabel;
    /// @notice names that ever said gm (for on-chain leaderboards)
    bytes32[] public gmLabels;
    /// @notice minted card ids in mint order (for the gallery)
    uint256[] public cardIds;
    uint256 public totalGm;

    struct GmView {
        string handle;
        bool hasCard;
        uint32 lastDay;
        uint32 streak; // current streak (0 if the chain was broken)
        uint32 best;
        uint32 total;
        uint32 shoutsSent;
        uint32 shoutsReceived;
    }

    event CardMinted(bytes32 indexed labelhash, address indexed holder, string handle);
    event GmSaid(bytes32 indexed labelhash, address indexed account, uint32 day, uint32 streak, uint32 total, string handle);
    event Shoutout(bytes32 indexed fromLabel, bytes32 indexed toLabel, string fromHandle, string toHandle);

    error NoAgentId();
    error AlreadyMinted();
    error AlreadyGmToday();
    error UnknownHandle();
    error SelfShoutout();
    error Soulbound();

    constructor(IAgentIdRegistry registry_, IAgentKudosStats kudos_) ERC721("AgentKudos Card", "KUDOS") {
        registry = registry_;
        kudos = kudos_;
    }

    // ---------------------------------------------------------------- actions

    /// @notice Mint your free Kudos Card (gas only). One per Agent ID, non-transferable.
    function mint() external {
        (bytes32 label, string memory handle) = _caller();
        uint256 id = uint256(label);
        if (_ownerOf(id) != address(0)) revert AlreadyMinted();
        _remember(label, handle);
        cardIds.push(id);
        _mint(msg.sender, id);
        emit CardMinted(label, msg.sender, handle);
    }

    /// @notice Daily check-in. Once per UTC day.
    function gm() external {
        (bytes32 label, string memory handle) = _caller();
        _gm(label, handle);
    }

    /// @notice Daily check-in that also sends a free gm shout-out to another registered name.
    function gm(string calldata to) external {
        (bytes32 label, string memory handle) = _caller();
        address toOwner = registry.ownerOfHandle(to);
        if (toOwner == address(0)) revert UnknownHandle();
        bytes32 toLabel = keccak256(bytes(to));
        if (toLabel == label) revert SelfShoutout();
        _gm(label, handle);
        _remember(toLabel, to);
        unchecked {
            gmOf[label].shoutsSent++;
            gmOf[toLabel].shoutsReceived++;
        }
        emit Shoutout(label, toLabel, handle, to);
    }

    // ---------------------------------------------------------------- views

    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    /// @notice Current streak, or 0 if the last gm was before yesterday.
    function currentStreak(bytes32 label) public view returns (uint32) {
        Gm storage g = gmOf[label];
        return g.lastDay + 1 >= today() ? g.streak : 0;
    }

    function canGmToday(address account) external view returns (bool) {
        string memory h = registry.handleOf(account);
        if (bytes(h).length == 0) return false;
        return gmOf[keccak256(bytes(h))].lastDay != today();
    }

    function totalSupply() external view returns (uint256) {
        return cardIds.length;
    }

    function gmCount() external view returns (uint256) {
        return gmLabels.length;
    }

    function statsOf(string calldata handle) public view returns (GmView memory v) {
        v = _view(keccak256(bytes(handle)));
        v.handle = handle;
    }

    function _view(bytes32 l) internal view returns (GmView memory v) {
        Gm memory g = gmOf[l];
        v.handle = handleOfLabel[l];
        v.hasCard = _ownerOf(uint256(l)) != address(0);
        v.lastDay = g.lastDay;
        v.streak = currentStreak(l);
        v.best = g.best;
        v.total = g.total;
        v.shoutsSent = g.shoutsSent;
        v.shoutsReceived = g.shoutsReceived;
    }

    /// @notice Paginated gm stats of every name that ever said gm (leaderboards).
    function getGmStats(uint256 start, uint256 count) external view returns (GmView[] memory out) {
        uint256 n = gmLabels.length;
        if (start >= n) return out;
        if (count > n - start) count = n - start;
        out = new GmView[](count);
        for (uint256 i; i < count; ++i) out[i] = _view(gmLabels[start + i]);
    }

    /// @notice Paginated handles of minted cards (gallery). Use tokenURI(uint256(keccak256(handle))) for art.
    function getCards(uint256 start, uint256 count) external view returns (string[] memory out) {
        uint256 n = cardIds.length;
        if (start >= n) return out;
        if (count > n - start) count = n - start;
        out = new string[](count);
        for (uint256 i; i < count; ++i) out[i] = handleOfLabel[bytes32(cardIds[start + i])];
    }

    function tierOf(uint32 streak) public pure returns (string memory name, string memory c1, string memory c2) {
        if (streak >= 30) return ("Legend", "#f5c542", "#ff5fa2");
        if (streak >= 14) return ("Diamond", "#5ee7ff", "#7c5cff");
        if (streak >= 7) return ("Gold", "#f5c542", "#ff8a3d");
        if (streak >= 3) return ("Silver", "#c9d3e3", "#6b7a99");
        return ("Bronze", "#d08b5b", "#5b3a29");
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        address holder = _requireOwned(id);
        bytes32 label = bytes32(id);
        string memory handle = handleOfLabel[label];
        Gm memory g = gmOf[label];
        g.streak = currentStreak(label);
        uint256 recv = _safeRecv(label);
        uint256 sent = _safeSent(holder);
        string memory image = Base64.encode(bytes(_svg(handle, g.streak, g.best, g.total, recv, sent)));
        bytes memory json = abi.encodePacked(
            '{"name":"', handle, '.ai Kudos Card","description":"Soulbound AgentKudos card for ', handle,
            '.ai. Shows the gm streak and kudos sent and received on BNB Chain.","image":"data:image/svg+xml;base64,',
            image, '","attributes":', _attrs(g, recv, sent), "}"
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function _attr(string memory k, uint256 v) internal pure returns (bytes memory) {
        return abi.encodePacked(',{"trait_type":"', k, '","display_type":"number","value":', v.toString(), "}");
    }

    function _attrs(Gm memory g, uint256 recv, uint256 sent) internal pure returns (bytes memory) {
        (string memory tier,,) = tierOf(g.streak);
        return abi.encodePacked(
            '[{"trait_type":"Tier","value":"', tier, '"}',
            _attr("Streak", g.streak), _attr("Best streak", g.best), _attr("Total gm", g.total),
            _attr("Kudos received", recv), _attr("Kudos sent", sent), "]"
        );
    }

    // ---------------------------------------------------------------- soulbound

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound(); // only mint is allowed
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }

    // ---------------------------------------------------------------- internal

    function _caller() internal view returns (bytes32 label, string memory handle) {
        handle = registry.handleOf(msg.sender);
        if (bytes(handle).length == 0) revert NoAgentId();
        label = keccak256(bytes(handle));
    }

    function _remember(bytes32 label, string memory handle) internal {
        if (bytes(handleOfLabel[label]).length == 0) handleOfLabel[label] = handle;
    }

    function _gm(bytes32 label, string memory handle) internal {
        Gm storage g = gmOf[label];
        uint32 d = today();
        if (g.lastDay == d) revert AlreadyGmToday();
        if (g.total == 0) gmLabels.push(label);
        _remember(label, handle);
        uint32 s = (g.lastDay != 0 && g.lastDay + 1 == d) ? g.streak + 1 : 1;
        g.streak = s;
        if (s > g.best) g.best = s;
        g.lastDay = d;
        unchecked {
            g.total++;
            totalGm++;
        }
        emit GmSaid(label, msg.sender, d, s, g.total, handle);
    }

    function _safeRecv(bytes32 label) internal view returns (uint256) {
        if (address(kudos).code.length == 0) return 0;
        try kudos.tipsReceived(label) returns (uint32 v) { return v; } catch { return 0; }
    }

    function _safeSent(address a) internal view returns (uint256) {
        if (address(kudos).code.length == 0) return 0;
        try kudos.tipsSent(a) returns (uint32 v) { return v; } catch { return 0; }
    }

    function _stat(string memory x, string memory label, string memory value) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="', x, '" y="372" class="v">', value, '</text><text x="', x, '" y="396" class="l">', label, "</text>"
        ));
    }

    function _svg(string memory handle, uint32 streak, uint32 best, uint32 total, uint256 recv, uint256 sent)
        internal
        pure
        returns (string memory)
    {
        (, string memory c1, string memory c2) = tierOf(streak);
        bytes memory head = abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 520" width="400" height="520">',
            '<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="', c1,
            '"/><stop offset="1" stop-color="', c2, '"/></linearGradient>',
            '<style>text{font-family:Inter,system-ui,sans-serif;fill:#fff}.v{font-size:30px;font-weight:800}.l{font-size:13px;fill:#aab3c5}.s{fill:url(#g)}</style><clipPath id="c"><rect width="400" height="520" rx="28"/></clipPath></defs>',
            '<rect width="400" height="520" rx="28" fill="#0d0f14"/><g clip-path="url(#c)"><circle cx="340" cy="70" r="130" fill="url(#g)" opacity=".18"/><circle cx="40" cy="520" r="110" fill="url(#g)" opacity=".08"/></g>',
            '<rect x="6" y="6" width="388" height="508" rx="24" fill="none" stroke="url(#g)" stroke-width="4"/>',
            '<text x="32" y="56" font-size="16" font-weight="700" class="s">AGENTKUDOS CARD</text>',
            '<text x="32" y="150" font-size="', bytes(handle).length > 12 ? "26" : "38", '" font-weight="800">', handle, '<tspan fill="#f5c542">.ai</tspan></text>'
        );
        (string memory tier,,) = tierOf(streak);
        bytes memory mid = abi.encodePacked(
            '<rect x="32" y="180" width="150" height="34" rx="17" fill="url(#g)"/><text x="107" y="203" font-size="15" font-weight="800" text-anchor="middle" fill="#111">',
            tier, ' tier</text>',
            '<text x="32" y="280" font-size="64" font-weight="900" class="s">', uint256(streak).toString(),
            '</text><text x="32" y="306" class="l">day gm streak  -  best ', uint256(best).toString(), "</text>"
        );
        bytes memory tail = abi.encodePacked(
            _stat("32", "total gm", uint256(total).toString()),
            _stat("152", "kudos in", recv.toString()),
            _stat("272", "kudos out", sent.toString()),
            '<text x="32" y="480" class="l">Soulbound - BNB Smart Chain - Agent ID</text></svg>'
        );
        return string(abi.encodePacked(head, mid, tail));
    }
}
