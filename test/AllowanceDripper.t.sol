// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/interfaces/IReactive.sol";
import { AllowanceDripper } from "../src/reactive/AllowanceDripper.sol";

/**
 * @notice Local tests for the reactive side. The SYSTEM contract lives at a
 *         hardcoded address (0x8888…8888); in the forge sandbox that address
 *         has no code, so subscribe / requestCallback calls against it
 *         succeed vacuously — enough to exercise our own logic. We impersonate
 *         SYSTEM with vm.prank to call react(), exactly like the network does.
 */
contract AllowanceDripperTest is Test {
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address internal constant CRON_EMITTER = 0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant CRON1000_TOPIC =
        0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;

    AllowanceDripper internal dripper;
    address internal vault = makeAddr("vault");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        // On Lasna the system contract has code; locally it doesn't, and
        // Solidity reverts calls to codeless addresses. Etch a stub (a single
        // STOP opcode) so subscribe / requestCallback calls succeed vacuously.
        vm.etch(SYSTEM, hex"00");
        dripper = new AllowanceDripper();
        dripper.setVault(vault);
    }

    function _cronLog(uint256 topic0_) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: 5_318_007,
            contractAddress: CRON_EMITTER,
            topic0: topic0_,
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: bytes(""),
            blockNumber: 0,
            opCode: 1,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    /// Due schedule + cron tick → drip triggered, schedule advanced from now.
    function test_react_triggersWhenDue() public {
        dripper.setSchedule(0.001 ether, 600, 0); // due immediately
        uint256 t0 = block.timestamp;

        vm.prank(SYSTEM);
        dripper.react(_cronLog(CRON1000_TOPIC));

        assertEq(dripper.releasesTriggered(), 1);
        assertEq(dripper.nextRelease(), t0 + 600);
    }

    /// Tick before the due time → nothing happens.
    function test_react_ignoresEarlyTick() public {
        dripper.setSchedule(0.001 ether, 600, 3600); // due in an hour

        vm.prank(SYSTEM);
        dripper.react(_cronLog(CRON1000_TOPIC));

        assertEq(dripper.releasesTriggered(), 0);
    }

    /// A log with a different topic is filtered out without reverting.
    function test_react_ignoresForeignTopic() public {
        dripper.setSchedule(0.001 ether, 600, 0);

        vm.prank(SYSTEM);
        dripper.react(_cronLog(0xdeadbeef));

        assertEq(dripper.releasesTriggered(), 0);
    }

    /// Paused dripper lets ticks pass.
    function test_react_ignoresWhenPaused() public {
        dripper.setSchedule(0.001 ether, 600, 0);
        dripper.setPaused(true);

        vm.prank(SYSTEM);
        dripper.react(_cronLog(CRON1000_TOPIC));

        assertEq(dripper.releasesTriggered(), 0);
    }

    /// Only the system contract may call react().
    function test_react_revertsForNonSystem() public {
        vm.prank(stranger);
        vm.expectRevert();
        dripper.react(_cronLog(CRON1000_TOPIC));
    }

    /// Owner controls are actually owner-only.
    function test_setters_areOwnerOnly() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        dripper.setVault(stranger);
        vm.expectRevert();
        dripper.setSchedule(1, 1, 1);
        vm.expectRevert();
        dripper.setPaused(true);
        vm.stopPrank();
    }
}
