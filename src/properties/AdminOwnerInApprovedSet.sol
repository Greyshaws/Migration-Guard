// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IMigrationProperty, PropertyResult, Severity} from "../IMigrationProperty.sol";

/// @notice Checks that an admin contract's owner is in an approved set.
/// @dev    Fails when:
///         (a) the contract has no code (not deployed), or
///         (b) the owner is the zero address (uninitialized), or
///         (c) the owner is not in the approved set (takeover or misconfiguration).
///
/// Reads storage directly via vm.load, so it works for unverified contracts
/// and custom auth schemes that don't expose a standard owner() getter.
contract AdminOwnerInApprovedSet is IMigrationProperty, Test {
    function id() external pure override returns (string memory) {
        return "auth.OwnerCheck";
    }

    function category() external pure override returns (string memory) {
        return "AUTH";
    }

    /// @param adminContract    Address of the contract whose owner we're checking
    /// @param ownerSlot        Storage slot where the owner address is stored
    /// @param approvedOwners   Allowed owner addresses (multisig, DAO, etc.)
    /// @return result          Pass/fail result with explanation
    function check(
        address adminContract,
        bytes32 ownerSlot,
        address[] memory approvedOwners
    ) external view returns (PropertyResult memory result) {
        // (a) Must be a deployed contract
        uint256 codeSize;
        assembly { codeSize := extcodesize(adminContract) }
        if (codeSize == 0) {
            return PropertyResult({
                ok: false,
                reason: "Admin contract has no code at this block (not deployed or selfdestructed)",
                severity: Severity.CRITICAL,
                evidence: abi.encode(adminContract, codeSize)
            });
        }

        // Read the owner slot directly. Works regardless of public getters.
        bytes32 raw = vm.load(adminContract, ownerSlot);
        address owner = address(uint160(uint256(raw)));

        // (b) Must not be uninitialized
        if (owner == address(0)) {
            return PropertyResult({
                ok: false,
                reason: "Admin contract owner is the zero address (uninitialized proxy)",
                severity: Severity.CRITICAL,
                evidence: abi.encode(adminContract, ownerSlot, owner)
            });
        }

        // (c) Must be in the approved set
        for (uint256 i = 0; i < approvedOwners.length; i++) {
            if (approvedOwners[i] == owner) {
                return PropertyResult({
                    ok: true,
                    reason: "",
                    severity: Severity.INFO,
                    evidence: abi.encode(adminContract, owner)
                });
            }
        }

        return PropertyResult({
            ok: false,
            reason: "Admin contract owner is not in the approved set",
            severity: Severity.CRITICAL,
            evidence: abi.encode(adminContract, ownerSlot, owner, approvedOwners)
        });
    }
}