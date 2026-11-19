// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AgentKudos} from "../src/AgentKudos.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";

/// Fork test against BSC mainnet and the real SPACE ID Agent ID registry.
/// Run: BSC_RPC_URL=https://bsc-dataseed.bnbchain.org forge test --match-contract Fork -vv
contract AgentKudosForkTest is Test {
    IAgentIdRegistry constant REG = IAgentIdRegistry(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address constant IKYYY = 0x39520082998E631C522d956efba23B288CeaF14c;
    address constant SKYARTS = 0xB948568A8cb230824cB1fb853d119102854e2EF7;
    address constant AZKAJEF = 0xB758bE9BD9178ccB4F51cCbFCc89A49e76E7AF55;
    address constant GGGAMING = 0xaB1df3971d5dD661b8d2fc4c5433427fA273192f;
    AgentKudos k;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC_URL", string("https://bsc-dataseed.bnbchain.org"));
        vm.createSelectFork(rpc);
        k = new AgentKudos(REG, USDT, USDC);
    }

    function test_fork_registryResolves() public view {
        assertEq(REG.handleOf(IKYYY), "ikyyy");
        assertEq(REG.handleOf(SKYARTS), "skyarts");
        assertEq(REG.handleOf(AZKAJEF), "azkajef");
        assertEq(REG.handleOf(GGGAMING), "gggaming");
        assertEq(REG.ownerOfHandle("ikyyy"), IKYYY);
        assertEq(REG.ownerOfHandle("gggaming"), GGGAMING);
        assertEq(REG.ownerOfHandle("this-is-not-valid"), address(0));
        assertTrue(k.isAgentIdHolder(SKYARTS));
        assertFalse(k.isAgentIdHolder(address(0xdead)));
    }

    function test_fork_tipNativeWithoutOptIn() public {
        uint256 before = IKYYY.balance;
        vm.deal(SKYARTS, 1 ether);
        vm.prank(SKYARTS);
        k.tip{value: 0.001 ether}("ikyyy", "gm from skyarts.ai");
        assertEq(IKYYY.balance - before, 0.001 ether);
        assertEq(address(k).balance, 0);
        assertEq(k.received(keccak256("ikyyy"), address(0)), 0.001 ether);
    }

    function test_fork_tipUsdtExactApproval() public {
        deal(USDT, GGGAMING, 10e18);
        uint256 before = IERC20(USDT).balanceOf(AZKAJEF);
        vm.startPrank(GGGAMING);
        IERC20(USDT).approve(address(k), 1e18);
        k.tipToken("azkajef", USDT, 1e18, "nice");
        vm.stopPrank();
        assertEq(IERC20(USDT).balanceOf(AZKAJEF) - before, 1e18);
        assertEq(IERC20(USDT).allowance(GGGAMING, address(k)), 0);
        assertEq(IERC20(USDT).balanceOf(address(k)), 0);
    }

    function test_fork_unregisteredHandleReverts() public {
        vm.deal(SKYARTS, 1 ether);
        vm.prank(SKYARTS);
        vm.expectRevert(AgentKudos.UnknownHandle.selector);
        k.tip{value: 1}("zzqqxx9871234", "");
    }

    function test_fork_bioAndProfile() public {
        vm.prank(GGGAMING);
        k.setBio("gaming");
        (bool registered,, string memory bio) = k.profileOf("gggaming");
        assertTrue(registered);
        assertEq(bio, "gaming");
        vm.prank(address(0xBEEF));
        vm.expectRevert(AgentKudos.NoAgentId.selector);
        k.setBio("x");
    }
}
