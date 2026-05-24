// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {TxOriginInAuthorization} from "../src/properties/TxOriginInAuthorization.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

contract TxOriginInAuthorizationTest is Test {
    // ---- Aevo case constants ----
    address constant PROXY_OWNER = 0x9D7b3586f361e3621Bf4F099cBC9d155e8ae6B76;
    uint256 constant BLOCK_POST_DEPLOYMENT = 23994254;
    uint256 constant BLOCK_PRE_DEPLOYMENT  = 23950000;

    TxOriginInAuthorization property;

    function setUp() public {
        property = new TxOriginInAuthorization();
        vm.makePersistent(address(property));
    }

    // ---- Unit tests for the scanner (no fork needed) ----

    /// Empty bytecode → no occurrences.
    function test_scanner_emptyCode() public view {
        bytes memory code = hex"";
        uint256[] memory offsets = property.scanForOrigin(code);
        assertEq(offsets.length, 0, "empty code should have no ORIGIN occurrences");
    }

    /// A standalone ORIGIN opcode → one occurrence at offset 0.
    function test_scanner_singleOrigin() public view {
        bytes memory code = hex"32";  // ORIGIN
        uint256[] memory offsets = property.scanForOrigin(code);
        assertEq(offsets.length, 1);
        assertEq(offsets[0], 0);
    }

    /// 0x32 appearing inside a PUSH1 operand → NOT counted as ORIGIN.
    /// This is the false-positive case the proper scanner must reject.
    function test_scanner_skipsPushOperand() public view {
        bytes memory code = hex"6032";  // PUSH1 0x32 (pushes number 50)
        uint256[] memory offsets = property.scanForOrigin(code);
        assertEq(offsets.length, 0, "0x32 as PUSH1 operand should not count");
    }

    /// PUSH followed by real ORIGIN later → exactly one occurrence at offset 2.
    function test_scanner_pushThenOrigin() public view {
        bytes memory code = hex"603232";  // PUSH1 0x32, then ORIGIN
        uint256[] memory offsets = property.scanForOrigin(code);
        assertEq(offsets.length, 1);
        assertEq(offsets[0], 2, "ORIGIN at position 2 (after PUSH1+operand)");
    }

    /// Larger PUSH: PUSH3 0x320000 → 0x32 in operand is skipped.
    function test_scanner_skipsLargerPushOperand() public view {
        bytes memory code = hex"62320000";  // PUSH3 0x320000
        uint256[] memory offsets = property.scanForOrigin(code);
        assertEq(offsets.length, 0);
    }

    // ---- Integration test against the Aevo ProxyOwner ----

    function test_failsOnAevoProxyOwner_realBytecode() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_POST_DEPLOYMENT);

        PropertyResult memory r = property.check(PROXY_OWNER);

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        // Decode evidence
        (, , uint256[] memory offsets) = abi.decode(r.evidence, (address, uint256, uint256[]));
        console.log("ORIGIN opcodes found:", offsets.length);
        for (uint256 i = 0; i < offsets.length; i++) {
            console.log("  - at byte offset:", offsets[i]);
        }

        assertFalse(r.ok, "should fail on Aevo ProxyOwner");
        assertEq(uint8(r.severity), uint8(Severity.HIGH));
        assertGt(offsets.length, 0, "must find at least one ORIGIN opcode");
    }

    function test_passesOnContractWithoutOrigin_realBytecode() public {
        // WETH9 — well-known contract, doesn't use tx.origin
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_POST_DEPLOYMENT);

        PropertyResult memory r = property.check(WETH);

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "WETH should not contain ORIGIN opcodes");
    }

    function test_failsOnNonContract() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_PRE_DEPLOYMENT);

        PropertyResult memory r = property.check(PROXY_OWNER);

        assertFalse(r.ok, "should fail when target has no code");
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }
}