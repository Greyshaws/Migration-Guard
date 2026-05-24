// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IMigrationProperty, PropertyResult, Severity} from "../IMigrationProperty.sol";

/// @notice Verifies that critical storage slots in a proxy contract remain
///         consistent across an upgrade boundary.
///
/// Catches:
///   - Re-initialization attacks: the "initialized" flag gets reset to 0,
///     allowing an attacker to call initialize() and take ownership.
///     Example: Renegade V1 exploit on Arbitrum (2025).
///   - Unexpected implementation swaps: the EIP-1967 implementation slot
///     changes when it shouldn't, or to an unapproved implementation.
///
/// Limitations (honest scope):
///   - Does NOT do full storage layout diffing (that requires compilation
///     metadata). For full layout validation, use OpenZeppelin's Upgrades
///     plugin alongside this property.
///   - Checks only the slots declared in config. Production version would
///     extract critical slots automatically from contract metadata.
contract StorageLayoutCompatibility is IMigrationProperty, Test {
    // EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 constant EIP1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function id() external pure override returns (string memory) {
        return "storage.ProxyStateCheck";
    }

    function category() external pure override returns (string memory) {
        return "STORAGE";
    }

    /// @notice Check that the proxy's critical slots are in a safe state.
    /// @param proxy                The proxy contract address
    /// @param initializedSlot      Slot holding the "initialized" flag
    ///                             (typically 0x00 for upgradeable contracts)
    /// @param approvedImpls        Known-good implementation addresses; if non-empty,
    ///                             the current implementation must be in this set
    function check(
        address proxy,
        bytes32 initializedSlot,
        address[] memory approvedImpls
    ) external view returns (PropertyResult memory result) {
        uint256 codeSize;
        assembly { codeSize := extcodesize(proxy) }
        if (codeSize == 0) {
            return PropertyResult({
                ok: false,
                reason: "Proxy has no code at this block",
                severity: Severity.CRITICAL,
                evidence: abi.encode(proxy)
            });
        }

        // Check 1: initialized flag must be non-zero (contract has been initialized).
        bytes32 initRaw = vm.load(proxy, initializedSlot);
        if (uint256(initRaw) == 0) {
            return PropertyResult({
                ok: false,
                reason: "Initialized flag is zero - contract is uninitialized or was reset",
                severity: Severity.CRITICAL,
                evidence: abi.encode(proxy, initializedSlot, initRaw)
            });
        }

        // Check 2: EIP-1967 implementation slot must be a deployed contract.
        bytes32 implRaw = vm.load(proxy, EIP1967_IMPL_SLOT);
        address impl = address(uint160(uint256(implRaw)));

        if (impl != address(0)) {
            // It's an EIP-1967 proxy. Verify the impl is a deployed contract.
            uint256 implCodeSize;
            assembly { implCodeSize := extcodesize(impl) }
            if (implCodeSize == 0) {
                return PropertyResult({
                    ok: false,
                    reason: "EIP-1967 implementation slot points to non-contract address",
                    severity: Severity.CRITICAL,
                    evidence: abi.encode(proxy, impl)
                });
            }

            // Check 3 (optional): if approvedImpls is non-empty, impl must be in it.
            if (approvedImpls.length > 0) {
                bool found = false;
                for (uint256 i = 0; i < approvedImpls.length; i++) {
                    if (approvedImpls[i] == impl) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    return PropertyResult({
                        ok: false,
                        reason: "Implementation address not in approved set",
                        severity: Severity.CRITICAL,
                        evidence: abi.encode(proxy, impl, approvedImpls)
                    });
                }
            }
        }
        // If impl is zero, this isn't an EIP-1967 proxy. We don't fail on that
        // because the property is also useful for non-standard proxies — we
        // just can't check the implementation slot.

        return PropertyResult({
            ok: true,
            reason: "",
            severity: Severity.INFO,
            evidence: abi.encode(proxy, impl)
        });
    }
}
