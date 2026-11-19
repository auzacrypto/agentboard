// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Test double for the SPACE ID Agent ID registry.
/// @dev Only implements the single function AgentBoard consumes:
///      balanceOf(address). Tests grant an "Agent ID" via `grant`.
contract MockAgentIdRegistry {
    mapping(address => uint256) private _balances;

    function grant(address who) external {
        _balances[who] = 1;
    }

    function revoke(address who) external {
        _balances[who] = 0;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}
