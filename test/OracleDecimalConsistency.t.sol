// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {OracleDecimalConsistency} from "../src/properties/OracleDecimalConsistency.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

contract OracleDecimalConsistencyTest is Test {
    // Chainlink ETH/USD on mainnet — returns 8-decimal prices
    address constant CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    // Victim vault (used as consumer for demo)
    address constant VICTIM_VAULT = 0x3c212A044760DE5a529B3Ba59363ddeCcc2210bE;

    uint256 constant POST_DEPLOYMENT_BLOCK = 23994254;

    OracleDecimalConsistency property;

    function setUp() public {
        property = new OracleDecimalConsistency();
        vm.makePersistent(address(property));
    }

    /// Oracle returns 8 decimals, consumer expects 8 — passes.
    function test_passesWhenDecimalsMatch() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), POST_DEPLOYMENT_BLOCK);

        PropertyResult memory r = property.check(CHAINLINK_ETH_USD, VICTIM_VAULT, 8);

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "8-decimal oracle should match 8-decimal expectation");
    }

    /// Oracle returns 8 decimals, consumer expects 18 — fails.
    /// This is the Aevo case: new oracle, old consumer scaling.
    function test_failsOnDecimalMismatch_aevoStyle() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), POST_DEPLOYMENT_BLOCK);

        PropertyResult memory r = property.check(CHAINLINK_ETH_USD, VICTIM_VAULT, 18);

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        (, , uint8 actual, uint8 expected) = abi.decode(
            r.evidence, (address, address, uint8, uint8)
        );
        console.log("Actual decimals:  ", actual);
        console.log("Expected decimals:", expected);

        assertFalse(r.ok, "should fail on decimal mismatch");
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
        assertEq(actual, 8);
        assertEq(expected, 18);
    }

    /// Non-contract oracle address — fails with "missing".
    function test_failsOnMissingOracle() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), POST_DEPLOYMENT_BLOCK);

        PropertyResult memory r = property.check(
            address(0xdead),
            VICTIM_VAULT,
            8
        );

        assertFalse(r.ok);
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }

    /// Oracle that doesn't expose decimals() — fails gracefully.
    function test_failsGracefullyWhenNoDecimalsFn() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), POST_DEPLOYMENT_BLOCK);

        // WETH doesn't have a decimals() that matches Chainlink's signature
        // (it returns 18 for its own token decimals, but that's separate from
        // an oracle's price decimals — for this test we just need a contract
        // that exists but isn't an oracle).
        // Actually WETH does have decimals() returning 18, so this test
        // would technically pass with expectedDecimals=18. Let's use a contract
        // that definitely doesn't have decimals().
        // Use the proxy admin from earlier — it definitely lacks decimals().
        address NOT_AN_ORACLE = 0x9D7b3586f361e3621Bf4F099cBC9d155e8ae6B76;

        PropertyResult memory r = property.check(NOT_AN_ORACLE, VICTIM_VAULT, 8);

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        assertFalse(r.ok, "should fail when oracle doesn't expose decimals()");
    }
}