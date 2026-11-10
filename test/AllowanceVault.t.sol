// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/interfaces/IPayable.sol";
import { AllowanceVault } from "../src/destination/AllowanceVault.sol";
import { MockCallbackProxy } from "./MockCallbackProxy.sol";

contract AllowanceVaultTest is Test {
    address internal constant DRIPPER = address(0xD211); // stand-in RSC address
    uint256 internal constant DRIP = 0.01 ether;

    MockCallbackProxy internal proxy;
    AllowanceVault internal vault;
    address internal alice = makeAddr("alice");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        proxy = new MockCallbackProxy();
        vault = new AllowanceVault(IPayable(payable(address(proxy))), DRIPPER);
        vm.deal(address(vault), 1 ether);
        vault.setRecipient(alice);
        vault.setDripAmount(DRIP);
    }

    /// Happy path: proxy delivers a callback from our dripper → recipient is
    /// paid exactly the vault's configured dripAmount, not the payload value.
    function test_release_paysConfiguredDrip() public {
        vm.prank(address(proxy));
        vault.release(DRIPPER, 999 ether); // payload amount must be ignored

        assertEq(alice.balance, DRIP);
        assertEq(vault.releasesPaid(), 1);
    }

    /// A random caller is rejected by onlyServiceProvider.
    function test_release_revertsForNonProxyCaller() public {
        vm.prank(stranger);
        vm.expectRevert();
        vault.release(DRIPPER, DRIP);
    }

    /// The proxy calling on behalf of a *different* reactive contract is
    /// rejected by onlyCallbackSender.
    function test_release_revertsForWrongReactiveSender() public {
        vm.prank(address(proxy));
        vm.expectRevert();
        vault.release(stranger, DRIP);
    }

    /// Low balance must skip quietly (no revert — a failed callback is
    /// charged in full anyway) and pay nothing.
    function test_release_skipsWhenInsufficientBalance() public {
        AllowanceVault poor = new AllowanceVault(IPayable(payable(address(proxy))), DRIPPER);
        poor.setRecipient(alice);
        poor.setDripAmount(DRIP);
        vm.deal(address(poor), DRIP - 1);

        vm.prank(address(proxy));
        poor.release(DRIPPER, DRIP); // must not revert

        assertEq(alice.balance, 0);
        assertEq(poor.releasesPaid(), 0);
    }

    /// Paused vault skips quietly.
    function test_release_skipsWhenPaused() public {
        vault.setPaused(true);

        vm.prank(address(proxy));
        vault.release(DRIPPER, DRIP);

        assertEq(alice.balance, 0);
        assertEq(vault.releasesPaid(), 0);
    }

    /// Owner controls are actually owner-only.
    function test_setters_areOwnerOnly() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        vault.setRecipient(stranger);
        vm.expectRevert();
        vault.setDripAmount(1 ether);
        vm.expectRevert();
        vault.setPaused(true);
        vm.stopPrank();
    }
}
