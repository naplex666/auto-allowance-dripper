// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractCallback } from "@reactive/base/AbstractCallback.sol";
import { IPayable } from "@reactive/interfaces/IPayable.sol";

/**
 * @title AllowanceVault — the destination half of the Auto-Allowance Dripper.
 * @notice Lives on Base Sepolia. Holds a pre-funded balance of (test) ETH and
 *         pays out one fixed drip to a configured recipient every time the
 *         AllowanceDripper reactive contract on Lasna tells it to.
 *
 *         The vault is deliberately *authoritative* about the money: the
 *         amount it pays is its own `dripAmount` state, set by the owner —
 *         never whatever a callback payload asks for. A misconfigured (or
 *         hypothetically compromised) reactive contract can therefore never
 *         drain more than one drip per callback.
 *
 * @dev    Callback authentication is two-layered, as the Omni docs require:
 *         - `onlyServiceProvider`: the caller must be this chain's callback
 *           proxy (the only address the network delivers callbacks through).
 *         - `onlyCallbackSender(reactive_)`: the first payload argument —
 *           which the network overwrites with the reactive contract's real
 *           address — must equal the immutable `_CALLBACK_SENDER` fixed at
 *           construction. Getting that address wrong at deploy time is
 *           unrecoverable; the vault would have to be redeployed.
 *
 *         Business failures (paused, no recipient, low balance, recipient
 *         rejecting the transfer) never revert: a failed callback is charged
 *         in full either way, so we record a `ReleaseSkipped`/`ReleaseFailed`
 *         event and return instead.
 */
contract AllowanceVault is AbstractCallback {
    /*//////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Deployer / administrator of the vault.
    address public owner;

    /// @notice Who receives each drip.
    address public recipient;

    /// @notice Fixed amount (in wei) paid out per release.
    uint256 public dripAmount;

    /// @notice While true, releases are skipped (funds stay put).
    bool public paused;

    /// @notice How many drips have been paid out so far.
    uint256 public releasesPaid;

    /*//////////////////////////////////////////////////////////////
                                  EVENTS
    //////////////////////////////////////////////////////////////*/

    event Released(address indexed recipient, uint256 amount, uint256 indexed releaseNumber);
    event ReleaseSkipped(string reason);
    event ReleaseFailed(address indexed recipient, uint256 amount);
    event RecipientUpdated(address recipient);
    event DripAmountUpdated(uint256 dripAmount);
    event PausedUpdated(bool paused);
    event Withdrawn(address indexed to, uint256 amount);
    event OwnershipTransferred(address newOwner);

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param callbackProxy_  Base Sepolia callback proxy
     *                        (0x476F44b11F5C942c58f4c8E3d0300E5710743585).
     * @param callbackSender_ Address of the AllowanceDripper on Lasna.
     *                        IMMUTABLE — deploy the dripper first.
     */
    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            CALLBACK ENTRY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Release one drip. Only callable by the callback proxy, and only
     *         on behalf of our AllowanceDripper.
     * @param reactive_       Injected by the network: the reactive contract's
     *                        address (we never choose this value — the payload
     *                        leaves a placeholder that the proxy overwrites).
     * @param requestedAmount_ What the dripper's schedule asked for. Kept for
     *                        observability; the vault pays its own configured
     *                        `dripAmount`, not this value.
     */
    function release(address reactive_, uint256 requestedAmount_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        // Silence the unused-parameter warning while keeping the value in the
        // signature for cross-checking against the dripper's schedule off-chain.
        requestedAmount_;

        if (paused) {
            emit ReleaseSkipped("paused");
            return;
        }
        if (recipient == address(0)) {
            emit ReleaseSkipped("no recipient");
            return;
        }
        if (dripAmount == 0) {
            emit ReleaseSkipped("no drip amount");
            return;
        }
        if (address(this).balance < dripAmount) {
            emit ReleaseSkipped("insufficient balance");
            return;
        }

        (bool success,) = payable(recipient).call{ value: dripAmount }("");
        if (!success) {
            emit ReleaseFailed(recipient, dripAmount);
            return;
        }

        releasesPaid += 1;
        emit Released(recipient, dripAmount, releasesPaid);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @notice Owner: set who receives the drips.
    function setRecipient(address recipient_) external onlyOwner {
        recipient = recipient_;
        emit RecipientUpdated(recipient_);
    }

    /// @notice Owner: set the fixed amount paid per release.
    function setDripAmount(uint256 dripAmount_) external onlyOwner {
        dripAmount = dripAmount_;
        emit DripAmountUpdated(dripAmount_);
    }

    /// @notice Owner: pause or resume releases.
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedUpdated(paused_);
    }

    /// @notice Owner: settle any outstanding debt to the callback proxy from
    ///         this contract's balance. Debt silently halts callback
    ///         delivery, so this escape hatch must exist from day one.
    function coverDebt() external onlyOwner {
        _coverDebt();
    }

    /// @notice Owner: withdraw funds (e.g. to retire or rebalance the vault).
    function withdraw(address to_, uint256 amount_) external onlyOwner {
        (bool success,) = payable(to_).call{ value: amount_ }("");
        require(success, "withdraw failed");
        emit Withdrawn(to_, amount_);
    }

    /// @notice Owner: hand administration to a new address.
    function transferOwnership(address newOwner_) external onlyOwner {
        owner = newOwner_;
        emit OwnershipTransferred(newOwner_);
    }
}
