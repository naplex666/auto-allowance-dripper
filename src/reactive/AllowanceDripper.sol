// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { AbstractReactive } from "@reactive/base/AbstractReactive.sol";
import { ISystemContract } from "@reactive/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/interfaces/IReactive.sol";

/**
 * @title AllowanceDripper — the reactive brain of the Auto-Allowance Dripper.
 * @notice Lives on Reactive Lasna testnet. It subscribes to the protocol's
 *         Cron1000 event (~17 minutes) and, whenever a scheduled release is
 *         due, asks the Reactive system contract to deliver a callback to the
 *         AllowanceVault on Base Sepolia, which then pays out a fixed drip.
 *
 *         Set it once (schedule + amount + vault), fund it, and forget it:
 *         no keeper, no bot, no button to press ever again.
 *
 * @dev    Omni pattern notes (these differ from legacy Reactive):
 *         - No RVM / `vm` modifier / `Callback` events. Subscriptions and
 *           callbacks both go through the SYSTEM contract (0x8888…8888).
 *         - `react()` must NEVER revert as a filter: a reverting reaction is
 *           still billed in full. Non-matching or not-yet-due ticks simply
 *           return as cheaply as possible, and the callback request itself is
 *           wrapped in try/catch for the same reason.
 *         - The first argument of every callback payload is an `address`
 *           placeholder passed as address(0); the network overwrites it with
 *           this contract's address so the vault can authenticate us.
 *         - All timing uses timestamps, never block numbers.
 */
contract AllowanceDripper is AbstractReactive {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Legacy system contract — the emitter of CRON events on Reactive.
    address internal constant CRON_EMITTER = 0x0000000000000000000000000000000000fffFfF;

    /// @notice topic0 of the Cron1000 event: fires every 1,000 Reactive blocks (~17 min).
    uint256 internal constant CRON1000_TOPIC =
        0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;

    /// @notice Destination chain for callbacks: Base Sepolia.
    uint256 public constant DESTINATION_CHAIN_ID = 84_532;

    /// @notice Gas limit handed to every callback. The protocol minimum is
    ///         100,000 and the callback proxy keeps its own settlement gas off
    ///         the top, so we follow the docs' example value of 1,000,000.
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    /*//////////////////////////////////////////////////////////////
                                  STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Deployer / administrator of the schedule.
    address public owner;

    /// @notice AllowanceVault contract address on Base Sepolia.
    address public vault;

    /// @notice Amount (in wei) each release asks the vault to pay out.
    uint256 public dripAmount;

    /// @notice Seconds between two releases.
    uint256 public interval;

    /// @notice Timestamp at or after which the next release is due.
    uint256 public nextRelease;

    /// @notice Soft pause: while true, ticks are ignored (subscription stays
    ///         alive). Use pauseCron() to also stop the per-tick billing.
    bool public paused;

    /// @notice How many releases have been triggered so far.
    uint256 public releasesTriggered;

    /*//////////////////////////////////////////////////////////////
                                  EVENTS
    //////////////////////////////////////////////////////////////*/

    event DripTriggered(uint256 indexed releaseNumber, uint256 nextRelease);
    event CallbackRequestFailed(uint256 at);
    event VaultUpdated(address vault);
    event ScheduleUpdated(uint256 dripAmount, uint256 interval, uint256 nextRelease);
    event PausedUpdated(bool paused);
    event CronSubscriptionUpdated(bool subscribed);
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
     * @notice Deploys the dripper and subscribes to Cron1000.
     * @dev    The constructor is payable so the contract can be seeded with
     *         lREACT at deployment; those funds pay for future reactions.
     *         The schedule itself is configured afterwards via setSchedule(),
     *         because the vault (destination of the callbacks) can only be
     *         deployed once this contract's address exists.
     */
    constructor() payable {
        owner = msg.sender;
        _subscribeCron();
    }

    /*//////////////////////////////////////////////////////////////
                            REACTIVE ENTRY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Called by the system contract for every log matching our
     *         subscription. Only Cron1000 ticks from the CRON emitter on this
     *         chain can match, but we re-check defensively and fall through
     *         silently for anything else — reverting here would still be
     *         billed in full.
     */
    function react(LogRecord calldata log_) external override onlySystem {
        // Defensive filter: not our cron tick → do nothing, cheaply.
        if (log_.topic0 != CRON1000_TOPIC || log_.contractAddress != CRON_EMITTER) {
            return;
        }

        // Not configured yet, paused, or not due yet → nothing to do.
        if (paused || vault == address(0) || dripAmount == 0 || interval == 0) {
            return;
        }
        if (block.timestamp < nextRelease) {
            return;
        }

        // Ask the vault on Base Sepolia to release this drip. The first
        // payload argument MUST be the address placeholder (address(0)):
        // the network replaces it with this contract's own address, which is
        // how the vault authenticates the callback.
        bytes memory payload = abi.encodeWithSignature("release(address,uint256)", address(0), dripAmount);

        try SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: DESTINATION_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        ) {
            // Advance the schedule from *now* (not from the old due time) so
            // a long downtime never turns into a burst of catch-up drips.
            nextRelease = block.timestamp + interval;
            releasesTriggered += 1;
            emit DripTriggered(releasesTriggered, nextRelease);
        } catch {
            // Leave nextRelease untouched: the next tick retries. Never
            // revert out of react() — the attempt is billed either way.
            emit CallbackRequestFailed(block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         SUBSCRIPTION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Subscribes to Cron1000. Arguments are centralized here because
    ///         unsubscribe() only works with an exact six-argument match.
    function _subscribeCron() internal {
        SYSTEM.subscribe(
            block.chainid, CRON_EMITTER, CRON1000_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @notice Removes the Cron1000 subscription (stops per-tick billing).
    function _unsubscribeCron() internal {
        SYSTEM.unsubscribe(
            block.chainid, CRON_EMITTER, CRON1000_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
    }

    /// @notice Owner: unsubscribe from CRON entirely (hard stop, no billing).
    function pauseCron() external onlyOwner {
        _unsubscribeCron();
        emit CronSubscriptionUpdated(false);
    }

    /// @notice Owner: re-subscribe to CRON after pauseCron().
    function resumeCron() external onlyOwner {
        _subscribeCron();
        emit CronSubscriptionUpdated(true);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @notice Owner: point the callbacks at the AllowanceVault (Base Sepolia).
    function setVault(address vault_) external onlyOwner {
        vault = vault_;
        emit VaultUpdated(vault_);
    }

    /**
     * @notice Owner: configure (or reconfigure) the drip schedule.
     * @param dripAmount_    Amount the vault is asked to release each time.
     * @param interval_      Seconds between releases.
     * @param firstIn_       Seconds from now until the first release is due
     *                       (0 = due at the very next cron tick).
     */
    function setSchedule(uint256 dripAmount_, uint256 interval_, uint256 firstIn_) external onlyOwner {
        dripAmount = dripAmount_;
        interval = interval_;
        nextRelease = block.timestamp + firstIn_;
        emit ScheduleUpdated(dripAmount_, interval_, nextRelease);
    }

    /// @notice Owner: soft-pause or resume reacting to ticks.
    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
        emit PausedUpdated(paused_);
    }

    /// @notice Owner: settle any outstanding debt to the system contract from
    ///         this contract's balance. Debt silently halts execution, so
    ///         this escape hatch must exist from day one.
    function coverDebt() external onlyOwner {
        _coverDebt();
    }

    /// @notice Owner: withdraw lREACT held by this contract (e.g. on retire).
    function withdraw(uint256 amount_) external onlyOwner {
        (bool success,) = payable(owner).call{ value: amount_ }("");
        require(success, "withdraw failed");
    }

    /// @notice Owner: hand administration to a new address.
    function transferOwnership(address newOwner_) external onlyOwner {
        owner = newOwner_;
        emit OwnershipTransferred(newOwner_);
    }
}
