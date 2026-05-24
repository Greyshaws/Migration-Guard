// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IMigrationProperty, PropertyResult, Severity} from "../IMigrationProperty.sol";

/// @notice Detects use of the ORIGIN opcode (tx.origin) in deployed bytecode.
/// @dev    tx.origin in authorization is a well-known anti-pattern: any contract
///         the legitimate owner interacts with can take admin actions on their
///         behalf. This property statically scans deployed bytecode for ORIGIN
///         opcodes, correctly handling PUSH operand data to avoid false positives.
///
/// This is a STATIC property — it does not require any storage reads or owner
/// context. It will catch the anti-pattern in any deployed contract regardless
/// of who owns it, when it was deployed, or what state it's in.
contract TxOriginInAuthorization is IMigrationProperty, Test {
    /// EVM opcode constants we care about.
    uint8 constant OP_ORIGIN  = 0x32;
    uint8 constant OP_PUSH1   = 0x60;
    uint8 constant OP_PUSH32  = 0x7f;

    function id() external pure override returns (string memory) {
        return "auth.DetectTxOrigin";
    }

    function category() external pure override returns (string memory) {
        return "AUTH";
    }

    /// @param target  Address of the contract to scan
    /// @return result Pass/fail with the location(s) of any ORIGIN opcodes found
    function check(address target) external view returns (PropertyResult memory result) {
        // Must be a deployed contract
        uint256 codeSize;
        assembly { codeSize := extcodesize(target) }
        if (codeSize == 0) {
            return PropertyResult({
                ok: false,
                reason: "Target has no code at this block (not deployed or selfdestructed)",
                severity: Severity.CRITICAL,
                evidence: abi.encode(target, codeSize)
            });
        }

        bytes memory code = target.code;
        uint256[] memory occurrences = scanForOrigin(code);

        if (occurrences.length == 0) {
            return PropertyResult({
                ok: true,
                reason: "",
                severity: Severity.INFO,
                evidence: abi.encode(target, codeSize)
            });
        }

        return PropertyResult({
            ok: false,
            reason: "ORIGIN opcode (tx.origin) detected in deployed bytecode",
            severity: Severity.HIGH,
            evidence: abi.encode(target, codeSize, occurrences)
        });
    }

    /// @dev   Walks the bytecode as a disassembler would: PUSH operand bytes
    ///        are skipped to avoid false positives from 0x32 appearing as data.
    /// @return offsets Byte offsets within `code` where ORIGIN opcodes appear.
    function scanForOrigin(bytes memory code) public pure returns (uint256[] memory offsets) {
        // First pass: count occurrences so we can size the result array.
        uint256 count = 0;
        uint256 i = 0;
        while (i < code.length) {
            uint8 op = uint8(code[i]);
            if (op == OP_ORIGIN) {
                count++;
                i++;
            } else if (op >= OP_PUSH1 && op <= OP_PUSH32) {
                // PUSHn: skip the next n bytes of operand data
                uint256 pushSize = op - OP_PUSH1 + 1;
                i += 1 + pushSize;
            } else {
                i++;
            }
        }

        // Second pass: record the offsets.
        offsets = new uint256[](count);
        uint256 idx = 0;
        i = 0;
        while (i < code.length) {
            uint8 op = uint8(code[i]);
            if (op == OP_ORIGIN) {
                offsets[idx++] = i;
                i++;
            } else if (op >= OP_PUSH1 && op <= OP_PUSH32) {
                uint256 pushSize = op - OP_PUSH1 + 1;
                i += 1 + pushSize;
            } else {
                i++;
            }
        }
    }
}