// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Read-only stats exposed by AgentKudos (0x5E1240848EA2fD922Cc75E5819ECd9c6850cE921).
interface IAgentKudosStats {
    function tipsReceived(bytes32 labelhash) external view returns (uint32);
    function tipsSent(address tipper) external view returns (uint32);
}
