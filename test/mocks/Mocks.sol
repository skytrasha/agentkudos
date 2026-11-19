// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAgentIdRegistry} from "../../src/interfaces/IAgentIdRegistry.sol";

contract MockRegistry is IAgentIdRegistry {
    mapping(address => string) public handleOf;
    mapping(bytes32 => address) internal owners;

    function set(address who, string calldata handle) external {
        handleOf[who] = handle;
        owners[keccak256(bytes(handle))] = who;
    }

    /// test helper: simulate a handle moving (not possible on mainnet, soulbound)
    function move(string calldata handle, address to) external {
        owners[keccak256(bytes(handle))] = to;
    }

    function balanceOf(address o) external view returns (uint256) {
        return bytes(handleOf[o]).length > 0 ? 1 : 0;
    }

    function ownerOfHandle(string calldata h) external view returns (address) {
        return owners[keccak256(bytes(h))];
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}
    function mint(address to, uint256 a) external { _mint(to, a); }
}

contract Rejecter {}

interface IKudos {
    function tip(string calldata, string calldata) external payable;
}

contract Reenterer {
    IKudos public k;
    string public target;
    bool public reentered;
    constructor(IKudos k_) { k = k_; }
    function setTarget(string calldata t) external { target = t; }
    receive() external payable {
        // try to re-enter while the outer tip is still executing
        try k.tip{value: msg.value}(target, "re") { reentered = true; } catch {}
    }
}
