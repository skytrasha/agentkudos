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

    function _open(address who) internal {
        vm.prank(who);
        k.openJar("gm");
    }

    function test_openJar() public {
        _open(alice);
        (bool open,, uint32 n, string memory bio) = k.jarOf("alice");
        assertTrue(open);
        assertEq(n, 0);
        assertEq(bio, "gm");
        assertEq(k.totalJars(), 1);
    }

    function test_openJar_requiresAgentId() public {
        vm.prank(carol);
        vm.expectRevert(AgentKudos.NoAgentId.selector);
        k.openJar("");
    }

    function test_openJar_twiceReverts() public {
        _open(alice);
        vm.prank(alice);
        vm.expectRevert(AgentKudos.JarAlreadyOpen.selector);
        k.openJar("");
    }

    function test_tipNative_forwardsImmediately() public {
        _open(alice);
        vm.expectEmit(true, true, true, true);
        emit Tipped(keccak256("alice"), bob, address(0), alice, 1 ether, "alice", "bob", "thanks!");
        vm.prank(bob);
        k.tip{value: 1 ether}("alice", "thanks!");
        assertEq(alice.balance, 1 ether);
        assertEq(address(k).balance, 0);
        assertEq(k.received(keccak256("alice"), address(0)), 1 ether);
        assertEq(k.sent(bob, address(0)), 1 ether);
        assertEq(k.tipsSent(bob), 1);
        assertEq(k.uniqueRecipients(bob), 1);
        assertEq(k.totalTips(), 1);
    }

    function test_tipFromNonHolder_hasEmptyFromHandle() public {
        _open(alice);
        vm.expectEmit(true, true, true, true);
        emit Tipped(keccak256("alice"), carol, address(0), alice, 1, "alice", "", "");
        vm.prank(carol);
        k.tip{value: 1}("alice", "");
    }

    function test_tip_unopenedJarReverts() public {
        vm.prank(bob);
        vm.expectRevert(AgentKudos.JarNotOpen.selector);
        k.tip{value: 1}("alice", "");
    }

    function test_tip_closedJarReverts() public {
        _open(alice);
        vm.prank(alice);
        k.closeJar();
        vm.prank(bob);
        vm.expectRevert(AgentKudos.JarNotOpen.selector);
        k.tip{value: 1}("alice", "");
        // reopen works and does not double count
        _open(alice);
        assertEq(k.totalJars(), 1);
    }

    function test_tip_selfReverts() public {
        _open(alice);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(AgentKudos.SelfTip.selector);
        k.tip{value: 1}("alice", "");
    }

    function test_tip_zeroReverts() public {
        _open(alice);
        vm.prank(bob);
        vm.expectRevert(AgentKudos.ZeroAmount.selector);
        k.tip("alice", "");
    }

    function test_tip_messageTooLong() public {
        _open(alice);
        bytes memory m = new bytes(281);
        vm.prank(bob);
        vm.expectRevert(AgentKudos.MessageTooLong.selector);
        k.tip{value: 1}("alice", string(m));
    }

    function test_tip_staleJarIfOwnerChanged() public {
        _open(alice);
        reg.move("alice", carol);
        vm.prank(bob);
        vm.expectRevert(AgentKudos.StaleJar.selector);
        k.tip{value: 1}("alice", "");
        (bool open,,,) = k.jarOf("alice");
        assertFalse(open);
    }

    function test_tipToken_exactAmountNoCustody() public {
        _open(alice);
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
        _open(alice);
        vm.startPrank(bob);
        usdt.approve(address(k), 1e18);
        vm.expectRevert();
        k.tipToken("alice", address(usdt), 2e18, "");
        vm.stopPrank();
    }

    function test_tipToken_unacceptedTokenReverts() public {
        _open(alice);
        vm.startPrank(bob);
        other.approve(address(k), 1e18);
        vm.expectRevert(AgentKudos.TokenNotAccepted.selector);
        k.tipToken("alice", address(other), 1e18, "");
        vm.expectRevert(AgentKudos.TokenNotAccepted.selector);
        k.tipToken("alice", address(0), 1e18, "");
        vm.stopPrank();
    }

    function test_uniqueRecipients() public {
        _open(alice);
        reg.set(carol, "carol");
        _open(carol);
        vm.startPrank(bob);
        k.tip{value: 1}("alice", "");
        k.tip{value: 1}("alice", "");
        k.tip{value: 1}("carol", "");
        vm.stopPrank();
        assertEq(k.uniqueRecipients(bob), 2);
        assertEq(k.tipsSent(bob), 3);
    }

    function test_leaderboardViews() public {
        _open(alice);
        reg.set(carol, "carol");
        _open(carol);
        vm.prank(alice);
        k.closeJar();
        _open(alice); // reopen must not duplicate
        vm.prank(bob);
        k.tip{value: 3}("alice", "");
        vm.startPrank(bob);
        usdt.approve(address(k), 7);
        k.tipToken("carol", address(usdt), 7, "");
        vm.stopPrank();
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        k.tip{value: 2}("carol", "");
        AgentKudos.JarView[] memory js = k.getJars(0, 10);
        assertEq(js.length, 2);
        assertEq(js[0].handle, "alice");
        assertEq(js[0].receivedNative, 3);
        assertEq(js[1].handle, "carol");
        assertEq(js[1].receivedTokenA, 7);
        assertEq(js[1].receivedNative, 2);
        assertEq(js[1].tipsReceived, 2);
        AgentKudos.TipperView[] memory ts = k.getTippers(0, 10);
        assertEq(ts.length, 2);
        assertEq(k.tipperCount(), 2);
        assertEq(ts[0].tipper, bob);
        assertEq(ts[0].handle, "bob");
        assertEq(ts[0].tipsSent, 2);
        assertEq(ts[0].uniqueRecipients, 2);
        assertEq(ts[1].handle, "alice");
        assertEq(k.getJars(5, 10).length, 0);
        assertEq(k.getJars(1, 10).length, 1);
    }

    function test_updateBio_onlyOwnJar() public {
        _open(alice);
        vm.prank(alice);
        k.updateBio("new");
        (,,, string memory bio) = k.jarOf("alice");
        assertEq(bio, "new");
        vm.prank(bob);
        vm.expectRevert(AgentKudos.JarNotOpen.selector);
        k.updateBio("x");
    }

    function test_rejectingRecipientRevertsWholeTip() public {
        Rejecter r = new Rejecter(); // no receive()
        reg.set(address(r), "rejecter");
        r.openJar(address(k), "");
        uint256 before = bob.balance;
        vm.prank(bob);
        vm.expectRevert(AgentKudos.ForwardFailed.selector);
        k.tip{value: 1 ether}("rejecter", "");
        assertEq(bob.balance, before);
    }

    function test_reentrancyBlocked() public {
        Reenterer r = new Reenterer(IKudos(address(k)));
        reg.set(address(r), "evil");
        r.open();
        _open(alice);
        r.setTarget("alice");
        vm.prank(bob);
        k.tip{value: 1 ether}("evil", "");
        assertFalse(r.reentered());
        assertEq(address(r).balance, 1 ether);
        assertEq(k.totalTips(), 1);
    }

    function test_noStrayFunctions() public {
        // contract has no receive/fallback: plain transfers are rejected, so nothing can get stuck
        vm.prank(bob);
        (bool ok,) = address(k).call{value: 1}("");
        assertFalse(ok);
    }

    function testFuzz_tipNative(uint96 amt, uint16 msgLen) public {
        vm.assume(amt > 0);
        msgLen = uint16(bound(msgLen, 0, 280));
        _open(alice);
        vm.deal(bob, amt);
        vm.prank(bob);
        k.tip{value: amt}("alice", string(new bytes(msgLen)));
        assertEq(alice.balance, amt);
        assertEq(address(k).balance, 0);
    }
}
