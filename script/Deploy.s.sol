// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentKudos} from "../src/AgentKudos.sol";
import {IAgentIdRegistry} from "../src/interfaces/IAgentIdRegistry.sol";

/// Option B (separate deployer EOA). Deploys through the canonical CREATE2 deployer so the address
/// equals deploy/predicted_address.txt. Run only after review:
///   forge script script/Deploy.s.sol --rpc-url bsc --account <keystore-name> --broadcast
/// (use an encrypted `cast wallet import` keystore; never paste a raw private key into a shell)
contract Deploy is Script {
    function run() external {
        bytes32 salt = keccak256("AgentKudos.v1");
        vm.startBroadcast();
        AgentKudos k = new AgentKudos{salt: salt}(
            IAgentIdRegistry(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F),
            0x55d398326f99059fF775485246999027B3197955, // USDT (BSC-USD)
            0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d // USDC
        );
        vm.stopBroadcast();
        console.log("AgentKudos deployed at", address(k));
    }
}
