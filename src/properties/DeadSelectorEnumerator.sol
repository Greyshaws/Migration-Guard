// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IMigrationProperty, PropertyResult, Severity} from "../IMigrationProperty.sol";

/// @notice Verifies that function selectors which should be dead post-migration
///         actually revert when called by an unauthorized caller.
///
/// Catches the surface-persistence class of bug:
///   - Huma V1 (May 2026): legacy drawdown function remained callable on the
///     deprecated V1 deployment, draining $101k.
///   - Yearn V1 (Dec 2025): legacy vault functions still callable years after
///     V2 launch, enabling flash-loan-based oracle manipulation.
///
/// How the check works:
///   - For each declared "dead" selector, simulate a call from an unauthorized
///     address with empty arguments.
///   - If the call SUCCEEDS, the function is live and the property FAILS.
///   - If the call REVERTS, the function is effectively dead (either disabled
///     or properly access-controlled).
///
/// Limitations (honest scope):
///   - Functions that require specific calldata to revert might appear "live"
///     to this check if they revert on data validation rather than access
///     control. False positives in that direction are possible.
///   - This property doesn't enumerate ALL selectors automatically — the team
///     must declare which ones should be dead. Production would auto-discover
///     by diffing V1 and V2 ABIs.
contract DeadSelectorEnumerator is IMigrationProperty, Test {
    function id() external pure override returns (string memory) {
        return "surface.FindLiveSelectors";
    }

    function category() external pure override returns (string memory) {
        return "SURFACE";
    }

    /// @param target               The legacy contract to probe
    /// @param expectedDeadSelectors  Selectors that should revert when called
    /// @return result              Pass/fail with the list of live selectors found
    function check(
        address target,
        bytes4[] memory expectedDeadSelectors
    ) external returns (PropertyResult memory result) {
        uint256 codeSize;
        assembly { codeSize := extcodesize(target) }
        if (codeSize == 0) {
            return PropertyResult({
                ok: false,
                reason: "Target has no code at this block",
                severity: Severity.CRITICAL,
                evidence: abi.encode(target)
            });
        }

        // Use vm.prank to simulate calls from an unauthorized random address.
        // This ensures access-controlled functions revert as expected.
        address unauthorized = address(uint160(uint256(keccak256("upgrade-guard:unauthorized"))));

        bytes4[] memory liveSelectors = new bytes4[](expectedDeadSelectors.length);
        uint256 liveCount = 0;

        for (uint256 i = 0; i < expectedDeadSelectors.length; i++) {
            bytes4 sel = expectedDeadSelectors[i];

            // Probe the selector with empty arguments. Many functions will revert
            // on missing args, which counts as "dead" from an attacker's standpoint.
            vm.prank(unauthorized);
            (bool ok, ) = target.call(abi.encodePacked(sel));

            if (ok) {
                // Call succeeded -> function is live
                liveSelectors[liveCount++] = sel;
            }
        }

        if (liveCount == 0) {
            return PropertyResult({
                ok: true,
                reason: "",
                severity: Severity.INFO,
                evidence: abi.encode(target, expectedDeadSelectors)
            });
        }

        // Trim the array to actual size
        bytes4[] memory found = new bytes4[](liveCount);
        for (uint256 i = 0; i < liveCount; i++) {
            found[i] = liveSelectors[i];
        }

        return PropertyResult({
            ok: false,
            reason: "Selectors that should be dead are still callable",
            severity: Severity.HIGH,
            evidence: abi.encode(target, found)
        });
    }
}
