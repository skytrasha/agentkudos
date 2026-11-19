// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentKudosCard} from "../src/AgentKudosCard.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";
import {IAgentKudosStats} from "../src/interfaces/IAgentKudosStats.sol";

/// Fork test against BSC mainnet: real Agent ID registry + the live AgentKudos contract.
contract AgentKudosCardForkTest is Test {
    IAgentIdRegistry constant REG = IAgentIdRegistry(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    IAgentKudosStats constant KUDOS = IAgentKudosStats(0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921);
    address constant IKYYY = 0x39520082998E631C522d956efba23B288CeaF14c;
    address constant AZKAJEF = 0xB758bE9BD9178ccB4F51cCbFCc89A49e76E7AF55;
    AgentKudosCard card;

    function setUp() public {
        vm.createSelectFork(vm.envOr("BSC_RPC_URL", string("https://bsc-dataseed.bnbchain.org")));
        card = new AgentKudosCard(REG, KUDOS);
    }

    function test_fork_mintGmShoutAndRender() public {
        vm.prank(IKYYY);
        card.mint();
        assertEq(card.ownerOf(uint256(keccak256("ikyyy"))), IKYYY);
        // same tokenId as the registry's Agent ID token
        assertEq(REG.ownerOfHandle("ikyyy"), IKYYY);
        vm.prank(IKYYY);
        card.gm("azkajef");
        vm.prank(AZKAJEF);
        card.gm();
        assertEq(card.statsOf("azkajef").shoutsReceived, 1);
        assertEq(card.statsOf("ikyyy").streak, 1);
        assertTrue(bytes(card.tokenURI(uint256(keccak256("ikyyy")))).length > 500);
    }

    function test_fork_nonHolderRejected() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(AgentKudosCard.NoAgentId.selector);
        card.mint();
        vm.prank(address(0xBEEF));
        vm.expectRevert(AgentKudosCard.NoAgentId.selector);
        card.gm();
    }

    function test_fork_shoutoutToUnregisteredRejected() public {
        vm.prank(AZKAJEF);
        vm.expectRevert(AgentKudosCard.UnknownHandle.selector);
        card.gm("zzqqxx9871234");
    }
}
