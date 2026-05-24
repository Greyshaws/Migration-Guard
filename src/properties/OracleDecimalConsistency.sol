// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IMigrationProperty, PropertyResult, Severity} from "../IMigrationProperty.sol";

interface IDecimals {
    function decimals() external view returns (uint8);
}

/// @notice Verifies that an oracle's decimal scale matches what its consumer expects.
/// @dev    Catches the scaling-drift class of bug:
///         - Aevo (Dec 2025): new oracle returned 18 decimals; legacy Ribbon
///           vaults assumed 8 decimals; payouts overstated by 10^10.
///         - Inverse Finance (Code4rena 2022): similar mismatch.
///         - Any case where a dependency is upgraded to a new decimal standard
///           but legacy consumers' scaling math wasn't updated.
contract OracleDecimalConsistency is IMigrationProperty, Test {
    function id() external pure override returns (string memory) {
        return "scaling.MatchOracleDecimals";
    }

    function category() external pure override returns (string memory) {
        return "SCALING";
    }

    /// @param oracle              The price feed contract
    /// @param consumer            The contract that reads from the oracle
    /// @param expectedDecimals    Decimal scale the consumer was built for
    /// @return result             Pass/fail with details
    function check(
        address oracle,
        address consumer,
        uint8 expectedDecimals
    ) external view returns (PropertyResult memory result) {
        // Both must be deployed contracts
        uint256 oracleCode;
        uint256 consumerCode;
        assembly {
            oracleCode := extcodesize(oracle)
            consumerCode := extcodesize(consumer)
        }
        if (oracleCode == 0) {
            return PropertyResult({
                ok: false,
                reason: "Oracle has no code at this block",
                severity: Severity.CRITICAL,
                evidence: abi.encode(oracle, "oracle missing")
            });
        }
        if (consumerCode == 0) {
            return PropertyResult({
                ok: false,
                reason: "Consumer has no code at this block",
                severity: Severity.CRITICAL,
                evidence: abi.encode(consumer, "consumer missing")
            });
        }

        // Call decimals() on the oracle
        (bool ok, bytes memory data) = oracle.staticcall(
            abi.encodeWithSelector(IDecimals.decimals.selector)
        );
        if (!ok || data.length < 32) {
            return PropertyResult({
                ok: false,
                reason: "Oracle does not expose decimals() - cannot verify scaling",
                severity: Severity.HIGH,
                evidence: abi.encode(oracle, "decimals() call failed")
            });
        }
        uint8 actualDecimals = abi.decode(data, (uint8));

        if (actualDecimals != expectedDecimals) {
            return PropertyResult({
                ok: false,
                reason: "Oracle decimals do not match consumer expectation",
                severity: Severity.CRITICAL,
                evidence: abi.encode(oracle, consumer, actualDecimals, expectedDecimals)
            });
        }

        return PropertyResult({
            ok: true,
            reason: "",
            severity: Severity.INFO,
            evidence: abi.encode(oracle, consumer, actualDecimals)
        });
    }
}