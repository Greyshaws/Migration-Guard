// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DeadSelectorEnumerator} from "../src/properties/DeadSelectorEnumerator.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

/// Mock contract simulating a legacy V1 with mixed wind-down state.
/// `deposit()` should be dead (the team meant to disable it post-migration).
/// `withdraw()` is intentionally live (users still need to exit).
contract LegacyMock {
    bool public depositsEnabled = true;  // BUG: team forgot to flip this to false

    function deposit() external view {
        // Imagine this should have been disabled; it's still callable.
        require(depositsEnabled, "deposits disabled");
    }

    function withdraw() external pure {
        // Intentionally live for stragglers
    }

    function adminOnly() external view {
        // Reverts unconditionally - effectively dead
        require(msg.sender == address(0xdead), "not admin");
    }
}

contract DeadSelectorEnumeratorTest is Test {
    address constant AEVO_PROXY_OWNER = 0x9D7b3586f361e3621Bf4F099cBC9d155e8ae6B76;
    uint256 constant BLOCK_POST_DEPLOYMENT = 23994254;

    DeadSelectorEnumerator property;
    LegacyMock legacy;

    function setUp() public {
        property = new DeadSelectorEnumerator();
        legacy = new LegacyMock();
        vm.makePersistent(address(property));
        vm.makePersistent(address(legacy));
    }

    /// On our mock: deposit() should be dead, adminOnly() should be dead.
    /// deposit() is INCORRECTLY still live -> property catches it.
    function test_failsWhenSupposedlyDeadFunctionIsLive() public {
        bytes4[] memory shouldBeDead = new bytes4[](2);
        shouldBeDead[0] = LegacyMock.deposit.selector;
        shouldBeDead[1] = LegacyMock.adminOnly.selector;

        PropertyResult memory r = property.check(address(legacy), shouldBeDead);

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        (, bytes4[] memory liveSelectors) = abi.decode(r.evidence, (address, bytes4[]));
        for (uint256 i = 0; i < liveSelectors.length; i++) {
            console.logBytes4(liveSelectors[i]);
        }

        assertFalse(r.ok, "should fail: deposit() is still callable");
        assertEq(uint8(r.severity), uint8(Severity.HIGH));
        assertEq(liveSelectors.length, 1, "exactly one live selector");
        assertEq(liveSelectors[0], LegacyMock.deposit.selector);
    }

    /// On our mock: only declare adminOnly as dead. It IS dead -> property passes.
    function test_passesWhenAllExpectedDeadAreActuallyDead() public {
        bytes4[] memory shouldBeDead = new bytes4[](1);
        shouldBeDead[0] = LegacyMock.adminOnly.selector;

        PropertyResult memory r = property.check(address(legacy), shouldBeDead);

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "adminOnly reverts so should be considered dead");
    }

    /// Non-contract target: fails with "no code".
    function test_failsOnNonContract() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 23950000);

        bytes4[] memory shouldBeDead = new bytes4[](1);
        shouldBeDead[0] = bytes4(0x12345678);

        PropertyResult memory r = property.check(AEVO_PROXY_OWNER, shouldBeDead);

        assertFalse(r.ok);
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }

    /// Integration: probe Aevo ProxyOwner with the f525a143 selector
    /// (the tx.origin-guarded setImpl wrapper from rekt.news). It should
    /// revert for our unauthorized caller. Property passes.
    function test_passesOnAevoProxyOwner_authGatedFunction() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_POST_DEPLOYMENT);

        bytes4[] memory shouldBeDead = new bytes4[](1);
        shouldBeDead[0] = bytes4(0xf525a143);  // the exploit's setImpl wrapper

        PropertyResult memory r = property.check(AEVO_PROXY_OWNER, shouldBeDead);

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "tx.origin-guarded function should revert for unauthorized caller");
    }
}
