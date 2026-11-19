// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Subset of the SPACE ID Agent ID registry (HandleRegistry) on BSC,
/// 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F. Handles are stored without the ".ai" suffix,
/// tokenId = uint256(keccak256(bytes(handle))), soulbound, one handle per address.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function handleOf(address owner) external view returns (string memory);
    function ownerOfHandle(string calldata handle) external view returns (address);
}
