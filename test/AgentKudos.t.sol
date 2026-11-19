// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentKudos} from "../src/AgentKudos.sol";
import {MockRegistry, MockToken, Rejecter, Reenterer, IKudos} from "./mocks/Mocks.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";

contract AgentKudosTest is Test {
    AgentKudos k;
    MockRegistry reg;
    MockToken usdt;
    MockToken usdc;
    MockToken other;

    address alice = makeAddr("alice"); // alice.ai
    address bob = makeAddr("bob"); // bob.ai
    address carol = makeAddr("carol"); // no Agent ID

    event Tipped(bytes32 indexed labelhash, address indexed from, address indexed token, address to, uint256 amount, string toHandle, string fromHandle, string message);
    event BioSet(bytes32 indexed labelhash, string handle, string bio);

    function setUp() public {
        reg = new MockRegistry();
        usdt = new MockToken();
        usdc = new MockToken();
        other = new MockToken();
        k = new AgentKudos(IAgentIdRegistry(address(reg)), address(usdt), address(usdc));
        reg.set(alice, "alice");
        reg.set(bob, "bob");
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        usdt.mint(bob, 1000e18);
        other.mint(bob, 1000e18);
    }

    function test_tipNative_noOptInNeeded() public {
        vm.expectEmit(true, true, true, true);
        emit Tipped(keccak256("alice"), bob, address(0), alice, 1 ether, "alice", "bob", "thanks!");
        vm.prank(bob);
        k.tip{value: 1 ether}("alice", "thanks!");
        assertEq(alice.balance, 1 ether);
        assertEq(address(k).balance, 0);
        assertEq(k.received(keccak256("alice"), address(0)), 1 ether);
        assertEq(k.sent(bob, address(0)), 1 ether);
        assertEq(k.tipsSent(bob), 1);
        assertEq(k.tipsReceived(keccak256("alice")), 1);
        assertEq(k.uniqueRecipients(bob), 1);
        assertEq(k.totalTips(), 1);
    }

    function test_tipFromNonHolder_hasEmptyFromHandle() public {
        vm.expectEmit(true, true, true, true);
        emit Tipped(keccak256("alice"), carol, address(0), alice, 1, "alice", "", "");
        vm.prank(carol);
        k.tip{value: 1}("alice", "");
    }

    function test_tip_unknownHandleReverts() public {
        vm.prank(bob);
        vm.expectRevert(AgentKudos.UnknownHandle.selector);
        k.tip{value: 1}("nobody", "");
        // handles are case-sensitive lowercase in the registry
        vm.prank(bob);
        vm.expectRevert(AgentKudos.UnknownHandle.selector);
        k.tip{value: 1}("Alice", "");
    }

    function test_tip_selfReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(AgentKudos.SelfTip.selector);
        k.tip{value: 1}("alice", "");
    }

    function test_tip_zeroReverts() public {
        vm.prank(bob);
        vm.expectRevert(AgentKudos.ZeroAmount.selector);
        k.tip("alice", "");
    }

    function test_tip_messageTooLong() public {
        bytes memory m = new bytes(281);
        vm.prank(bob);
        vm.expectRevert(AgentKudos.MessageTooLong.selector);
        k.tip{value: 1}("alice", string(m));
    }

    function test_tip_followsCurrentOwner() public {
        reg.move("alice", carol); // impossible on mainnet (soulbound); checks resolution happens at tip time
        vm.prank(bob);
        k.tip{value: 1}("alice", "");
        assertEq(carol.balance, 10 ether + 1);
        assertEq(alice.balance, 0);
    }

    function test_tipToken_exactAmountNoCustody() public {
        vm.startPrank(bob);
        usdt.approve(address(k), 5e18);
        k.tipToken("alice", address(usdt), 5e18, "coffee");
        vm.stopPrank();
        assertEq(usdt.balanceOf(alice), 5e18);
        assertEq(usdt.balanceOf(address(k)), 0);
        assertEq(usdt.allowance(bob, address(k)), 0); // exact approval fully consumed
        assertEq(k.received(keccak256("alice"), address(usdt)), 5e18);
    }

    function test_tipToken_insufficientAllowanceReverts() public {
        vm.startPrank(bob);
        usdt.approve(address(k), 1e18);
        vm.expectRevert();
        k.tipToken("alice", address(usdt), 2e18, "");
        vm.stopPrank();
    }

    function test_tipToken_unknownHandleReverts() public {
        vm.startPrank(bob);
        usdt.approve(address(k), 1e18);
        vm.expectRevert(AgentKudos.UnknownHandle.selector);
        k.tipToken("nobody", address(usdt), 1e18, "");
        vm.stopPrank();
    }

    function test_tipToken_unacceptedTokenReverts() public {
        vm.startPrank(bob);
        other.approve(address(k), 1e18);
        vm.expectRevert(AgentKudos.TokenNotAccepted.selector);
        k.tipToken("alice", address(other), 1e18, "");
        vm.expectRevert(AgentKudos.TokenNotAccepted.selector);
        k.tipToken("alice", address(0), 1e18, "");
        vm.stopPrank();
    }

    function test_uniqueRecipients() public {
        reg.set(carol, "carol");
        vm.startPrank(bob);
        k.tip{value: 1}("alice", "");
        k.tip{value: 1}("alice", "");
        k.tip{value: 1}("carol", "");
        vm.stopPrank();
        assertEq(k.uniqueRecipients(bob), 2);
        assertEq(k.tipsSent(bob), 3);
    }

    function test_setBio_optional() public {
        vm.expectEmit(true, false, false, true);
        emit BioSet(keccak256("alice"), "alice", "builder");
        vm.prank(alice);
        k.setBio("builder");
        (bool registered, uint32 tips, string memory bio) = k.profileOf("alice");
        assertTrue(registered);
        assertEq(tips, 0);
        assertEq(bio, "builder");
        (registered,,) = k.profileOf("nobody");
        assertFalse(registered);
    }

    function test_setBio_requiresAgentId() public {
        vm.prank(carol);
        vm.expectRevert(AgentKudos.NoAgentId.selector);
        k.setBio("x");
    }

    function test_setBio_tooLong() public {
        vm.prank(alice);
        vm.expectRevert(AgentKudos.BioTooLong.selector);
        k.setBio(string(new bytes(161)));
    }

    function test_leaderboardViews() public {
        reg.set(carol, "carol");
        vm.prank(bob);
        k.tip{value: 3}("alice", "");
        vm.startPrank(bob);
        usdt.approve(address(k), 7);
        k.tipToken("carol", address(usdt), 7, "");
        vm.stopPrank();
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        k.tip{value: 2}("carol", "");
        AgentKudos.RecipientView[] memory rs = k.getRecipients(0, 10);
        assertEq(rs.length, 2);
        assertEq(k.recipientCount(), 2);
        assertEq(rs[0].handle, "alice");
        assertEq(rs[0].receivedNative, 3);
        assertEq(rs[1].handle, "carol");
        assertEq(rs[1].receivedTokenA, 7);
        assertEq(rs[1].receivedNative, 2);
        assertEq(rs[1].tipsReceived, 2);
        AgentKudos.TipperView[] memory ts = k.getTippers(0, 10);
        assertEq(ts.length, 2);
        assertEq(k.tipperCount(), 2);
        assertEq(ts[0].tipper, bob);
        assertEq(ts[0].handle, "bob");
        assertEq(ts[0].tipsSent, 2);
        assertEq(ts[0].uniqueRecipients, 2);
        assertEq(ts[1].handle, "alice");
        assertEq(k.getRecipients(5, 10).length, 0);
        assertEq(k.getRecipients(1, 10).length, 1);
    }

    function test_rejectingRecipientRevertsWholeTip() public {
        Rejecter r = new Rejecter(); // no receive()
        reg.set(address(r), "rejecter");
        uint256 before = bob.balance;
        vm.prank(bob);
        vm.expectRevert(AgentKudos.ForwardFailed.selector);
        k.tip{value: 1 ether}("rejecter", "");
        assertEq(bob.balance, before);
    }

    function test_reentrancyBlocked() public {
        Reenterer r = new Reenterer(IKudos(address(k)));
        reg.set(address(r), "evil");
        r.setTarget("alice");
        vm.prank(bob);
        k.tip{value: 1 ether}("evil", "");
        assertFalse(r.reentered());
        assertEq(address(r).balance, 1 ether);
        assertEq(k.totalTips(), 1);
    }

    function test_noStrayFunctions() public {
        // no receive/fallback: plain transfers are rejected, so nothing can get stuck
        vm.prank(bob);
        (bool ok,) = address(k).call{value: 1}("");
        assertFalse(ok);
    }

    function testFuzz_tipNative(uint96 amt, uint16 msgLen) public {
        vm.assume(amt > 0);
        msgLen = uint16(bound(msgLen, 0, 280));
        vm.deal(bob, amt);
        vm.prank(bob);
        k.tip{value: amt}("alice", string(new bytes(msgLen)));
        assertEq(alice.balance, amt);
        assertEq(address(k).balance, 0);
    }
}
