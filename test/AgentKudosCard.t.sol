// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {AgentKudos} from "../src/AgentKudos.sol";
import {AgentKudosCard} from "../src/AgentKudosCard.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";
import {IAgentKudosStats} from "../src/interfaces/IAgentKudosStats.sol";
import {MockRegistry} from "./mocks/Mocks.sol";

contract AgentKudosCardTest is Test {
    MockRegistry reg;
    AgentKudos kudos;
    AgentKudosCard card;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol"); // no Agent ID

    event GmSaid(bytes32 indexed labelhash, address indexed account, uint32 day, uint32 streak, uint32 total, string handle);
    event Shoutout(bytes32 indexed fromLabel, bytes32 indexed toLabel, string fromHandle, string toHandle);
    event CardMinted(bytes32 indexed labelhash, address indexed holder, string handle);

    function setUp() public {
        vm.warp(1_795_000_000);
        reg = new MockRegistry();
        kudos = new AgentKudos(IAgentIdRegistry(address(reg)), address(0x1111), address(0x2222));
        card = new AgentKudosCard(IAgentIdRegistry(address(reg)), IAgentKudosStats(address(kudos)));
        reg.set(alice, "alice");
        reg.set(bob, "bob");
    }

    function _id(string memory h) internal pure returns (uint256) {
        return uint256(keccak256(bytes(h)));
    }

    function test_mint_onePerAgentId() public {
        vm.expectEmit(true, true, false, true);
        emit CardMinted(keccak256("alice"), alice, "alice");
        vm.prank(alice);
        card.mint();
        assertEq(card.ownerOf(_id("alice")), alice);
        assertEq(card.balanceOf(alice), 1);
        assertEq(card.totalSupply(), 1);
        vm.prank(alice);
        vm.expectRevert(AgentKudosCard.AlreadyMinted.selector);
        card.mint();
    }

    function test_mint_requiresAgentId() public {
        vm.prank(carol);
        vm.expectRevert(AgentKudosCard.NoAgentId.selector);
        card.mint();
    }

    function test_soulbound() public {
        vm.prank(alice);
        card.mint();
        vm.startPrank(alice);
        vm.expectRevert(AgentKudosCard.Soulbound.selector);
        card.transferFrom(alice, bob, _id("alice"));
        vm.expectRevert(AgentKudosCard.Soulbound.selector);
        card.safeTransferFrom(alice, bob, _id("alice"));
        vm.expectRevert(AgentKudosCard.Soulbound.selector);
        card.approve(bob, _id("alice"));
        vm.expectRevert(AgentKudosCard.Soulbound.selector);
        card.setApprovalForAll(bob, true);
        vm.stopPrank();
    }

    function test_gm_oncePerDay_andStreaks() public {
        uint32 d = card.today();
        vm.expectEmit(true, true, false, true);
        emit GmSaid(keccak256("alice"), alice, d, 1, 1, "alice");
        vm.prank(alice);
        card.gm();
        vm.prank(alice);
        vm.expectRevert(AgentKudosCard.AlreadyGmToday.selector);
        card.gm();
        assertFalse(card.canGmToday(alice));
        // next two days -> streak 3
        for (uint256 i = 1; i <= 2; i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(alice);
            card.gm();
        }
        AgentKudosCard.GmView memory v = card.statsOf("alice");
        assertEq(v.streak, 3);
        assertEq(v.best, 3);
        assertEq(v.total, 3);
        // skip a day -> current streak shows 0, next gm restarts at 1, best stays 3
        vm.warp(block.timestamp + 2 days);
        assertEq(card.statsOf("alice").streak, 0);
        vm.prank(alice);
        card.gm();
        v = card.statsOf("alice");
        assertEq(v.streak, 1);
        assertEq(v.best, 3);
        assertEq(v.total, 4);
        assertEq(card.totalGm(), 4);
        assertEq(card.gmCount(), 1);
    }

    function test_gm_requiresAgentId() public {
        vm.prank(carol);
        vm.expectRevert(AgentKudosCard.NoAgentId.selector);
        card.gm();
        assertFalse(card.canGmToday(carol));
    }

    function test_gmShoutout() public {
        vm.expectEmit(true, true, false, true);
        emit Shoutout(keccak256("alice"), keccak256("bob"), "alice", "bob");
        vm.prank(alice);
        card.gm("bob");
        assertEq(card.statsOf("alice").shoutsSent, 1);
        assertEq(card.statsOf("bob").shoutsReceived, 1);
        assertEq(card.statsOf("alice").total, 1); // counts as today's gm
        vm.prank(alice);
        vm.expectRevert(AgentKudosCard.AlreadyGmToday.selector);
        card.gm("bob");
    }

    function test_gmShoutout_validation() public {
        vm.startPrank(alice);
        vm.expectRevert(AgentKudosCard.UnknownHandle.selector);
        card.gm("nobody");
        vm.expectRevert(AgentKudosCard.SelfShoutout.selector);
        card.gm("alice");
        vm.stopPrank();
    }

    function test_noValueAccepted() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(card).call{value: 1}(abi.encodeWithSignature("gm()"));
        assertFalse(ok);
        (ok,) = address(card).call{value: 1}("");
        assertFalse(ok);
    }

    function test_leaderboardAndGallery() public {
        vm.prank(alice);
        card.mint();
        vm.prank(bob);
        card.mint();
        vm.prank(alice);
        card.gm();
        vm.prank(bob);
        card.gm("alice");
        string[] memory cs = card.getCards(0, 10);
        assertEq(cs.length, 2);
        assertEq(cs[0], "alice");
        assertEq(cs[1], "bob");
        AgentKudosCard.GmView[] memory gs = card.getGmStats(0, 10);
        assertEq(gs.length, 2);
        assertEq(gs[0].handle, "alice");
        assertTrue(gs[0].hasCard);
        assertEq(gs[0].shoutsReceived, 1);
        assertEq(gs[1].handle, "bob");
        assertEq(card.getGmStats(2, 10).length, 0);
    }

    function test_tokenURI_onchainSvgWithStats() public {
        vm.prank(alice);
        card.mint();
        vm.prank(alice);
        card.gm();
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        kudos.tip{value: 1}("alice", "gm");
        string memory uri = card.tokenURI(_id("alice"));
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
        string memory json = string(_b64decode(_slice(uri, 29)));
        assertTrue(_contains(json, '"name":"alice.ai Kudos Card"'));
        assertTrue(_contains(json, '"trait_type":"Kudos received","display_type":"number","value":1'));
        assertTrue(_contains(json, '"trait_type":"Streak","display_type":"number","value":1'));
        assertTrue(_contains(json, '"value":"Bronze"'));
        assertTrue(_contains(json, "data:image/svg+xml;base64,"));
    }

    function test_tierProgression() public view {
        (string memory t,,) = card.tierOf(1);
        assertEq(t, "Bronze");
        (t,,) = card.tierOf(3);
        assertEq(t, "Silver");
        (t,,) = card.tierOf(7);
        assertEq(t, "Gold");
        (t,,) = card.tierOf(14);
        assertEq(t, "Diamond");
        (t,,) = card.tierOf(30);
        assertEq(t, "Legend");
    }

    function test_tokenURI_survivesBrokenStatsContract() public {
        AgentKudosCard c2 = new AgentKudosCard(IAgentIdRegistry(address(reg)), IAgentKudosStats(address(0xdead)));
        vm.prank(alice);
        c2.mint();
        assertTrue(bytes(c2.tokenURI(_id("alice"))).length > 100);
    }

    // ---- helpers
    function _startsWith(string memory s, string memory p) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(p);
        if (a.length < b.length) return false;
        for (uint256 i; i < b.length; i++) if (a[i] != b[i]) return false;
        return true;
    }

    function _contains(string memory s, string memory p) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(p);
        if (b.length > a.length) return false;
        for (uint256 i; i + b.length <= a.length; i++) {
            bool ok = true;
            for (uint256 j; j < b.length; j++) if (a[i + j] != b[j]) { ok = false; break; }
            if (ok) return true;
        }
        return false;
    }

    function _slice(string memory s, uint256 from) internal pure returns (string memory) {
        bytes memory a = bytes(s);
        bytes memory o = new bytes(a.length - from);
        for (uint256 i; i < o.length; i++) o[i] = a[from + i];
        return string(o);
    }

    function _b64decode(string memory s) internal pure returns (bytes memory) {
        bytes memory t = bytes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/");
        uint8[128] memory m;
        for (uint8 i; i < 64; i++) m[uint8(t[i])] = i;
        bytes memory d = bytes(s);
        uint256 pad = d[d.length - 1] == "=" ? (d[d.length - 2] == "=" ? 2 : 1) : 0;
        bytes memory o = new bytes(d.length / 4 * 3 - pad);
        uint256 k;
        for (uint256 i; i < d.length; i += 4) {
            uint256 n = (uint256(m[uint8(d[i])]) << 18) | (uint256(m[uint8(d[i + 1])]) << 12)
                | (uint256(d[i + 2] == "=" ? 0 : m[uint8(d[i + 2])]) << 6) | uint256(d[i + 3] == "=" ? 0 : m[uint8(d[i + 3])]);
            if (k < o.length) o[k++] = bytes1(uint8(n >> 16));
            if (k < o.length) o[k++] = bytes1(uint8(n >> 8));
            if (k < o.length) o[k++] = bytes1(uint8(n));
        }
        return o;
    }
}
