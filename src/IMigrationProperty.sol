// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// Severity levels for property check results.
enum Severity {
    INFO,
    LOW,
    MEDIUM,
    HIGH,
    CRITICAL
}

/// Result returned by every property's check function.
struct PropertyResult {
    bool ok;            // true = property holds, false = violated
    string reason;      // human-readable explanation
    Severity severity;  // how bad is the violation
    bytes evidence;     // optional structured data (block, addresses, etc.)
}

/// All properties in the library implement this interface.
interface IMigrationProperty {
    function id() external pure returns (string memory);
    function category() external pure returns (string memory);
}