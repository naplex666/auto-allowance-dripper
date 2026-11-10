// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/**
 * @title MockCallbackProxy
 * @notice Test stand-in for a chain's Reactive callback proxy. The vault only
 *         ever interacts with its proxy through two surface points: the proxy
 *         is the *caller* of the callback (checked by `onlyServiceProvider`),
 *         and `debt(address)` / value transfers for debt settlement
 *         (AbstractPayer). This mock covers both.
 */
contract MockCallbackProxy {
    mapping(address => uint256) private _debts;

    function debt(address contract_) external view returns (uint256) {
        return _debts[contract_];
    }

    function setDebt(address contract_, uint256 amount_) external {
        _debts[contract_] = amount_;
    }

    receive() external payable { }
}
