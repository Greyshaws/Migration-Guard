// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StorageLayoutCompatibility} from "../src/properties/StorageLayoutCompatibility.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

/// Minimal contract used to simulate a proxy. Has empty bytecode that
/// makes `extcodesize` non-zero, and storage we control via vm.store.
contract MockProxy {
    // Constructor leaves the contract with non-empty code.
    function placeholder() external pure returns (uint256) { return 1; }
}

/// A second mock used as the "implementation" the proxy points to.
contract MockImpl {
    function placeholder() external pure returns (uint256) { return 2; }
}

contract StorageLayoutCompatibilityTest is Test {
    address constant AEVO_PROXY_OWNER = 0x9D7b3586f361e3621Bf4F099cBC9d155e8ae6B76;
    uint256 constant BLOCK_POST_DEPLOYMENT = 23994254;

    bytes32 constant EIP1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    StorageLayoutCompatibility property;
    MockProxy proxy;
    MockImpl impl;

    function setUp() public {
        property = new StorageLayoutCompatibility();
        proxy = new MockProxy();
        impl = new MockImpl();
        vm.makePersistent(address(property));
        vm.makePersistent(address(proxy));
        vm.makePersistent(address(impl));
    }

    /// Configure proxy as a valid EIP-1967 proxy pointing to a real impl,
    /// with initialized=1. Should pass.
    function test_passesOnValidEip1967Proxy() public {
        // Slot 0 holds something non-zero (the initialized flag, or owner, etc.)
        vm.store(address(proxy), bytes32(uint256(0)), bytes32(uint256(1)));
        // EIP-1967 impl slot points to our MockImpl
        vm.store(address(proxy), EIP1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        address[] memory approved = new address[](0);
        PropertyResult memory r = property.check(
            address(proxy),
            bytes32(uint256(0)),
            approved
        );

        (, address implFound) = abi.decode(r.evidence, (address, address));
        console.log("Implementation found:", implFound);

        assertTrue(r.ok, "valid EIP-1967 proxy should pass");
        assertEq(implFound, address(impl));
    }

    /// Same setup, but with approvedImpls excluding our impl. Should fail.
    function test_failsWhenImplNotInApprovedSet() public {
        vm.store(address(proxy), bytes32(uint256(0)), bytes32(uint256(1)));
        vm.store(address(proxy), EIP1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        address[] memory approved = new address[](1);
        approved[0] = address(0xdeadbeef);

        PropertyResult memory r = property.check(
            address(proxy),
            bytes32(uint256(0)),
            approved
        );

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        assertFalse(r.ok, "should fail when impl is not in approved set");
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }

    /// Initialized flag is zero. Should fail (re-init attack class).
    function test_failsWhenInitializedFlagIsZero() public {
        // Slot 0 deliberately zero
        vm.store(address(proxy), bytes32(uint256(0)), bytes32(uint256(0)));
        // Impl slot still set, just to be clear about which check fires first
        vm.store(address(proxy), EIP1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        address[] memory approved = new address[](0);
        PropertyResult memory r = property.check(
            address(proxy),
            bytes32(uint256(0)),
            approved
        );

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        assertFalse(r.ok, "should fail when initialized flag is zero");
    }

    /// EIP-1967 impl slot points to a non-contract address. Should fail.
    function test_failsWhenImplIsNotContract() public {
        vm.store(address(proxy), bytes32(uint256(0)), bytes32(uint256(1)));
        // Point impl slot at an EOA (no code)
        vm.store(address(proxy), EIP1967_IMPL_SLOT, bytes32(uint256(uint160(address(0xc0ffee)))));

        address[] memory approved = new address[](0);
        PropertyResult memory r = property.check(
            address(proxy),
            bytes32(uint256(0)),
            approved
        );

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        assertFalse(r.ok, "should fail when impl points to non-contract");
    }

    /// Non-contract target: fails with "no code".
    function test_failsOnNonContract() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 23950000);

        address[] memory approved = new address[](0);
        PropertyResult memory r = property.check(
            AEVO_PROXY_OWNER,  // didn't exist at this block
            bytes32(uint256(0)),
            approved
        );

        assertFalse(r.ok);
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }

    /// Integration with real mainnet contract: Aevo ProxyOwner is not an
    /// EIP-1967 proxy and has a non-zero slot 0, so it should pass — this
    /// property catches a different class of bug than the Aevo exploit.
    function test_passesOnAevoProxyOwner_realMainnet() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_POST_DEPLOYMENT);

        address[] memory approved = new address[](0);
        PropertyResult memory r = property.check(
            AEVO_PROXY_OWNER,
            bytes32(uint256(0)),
            approved
        );

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "Aevo ProxyOwner has non-zero slot 0 and no EIP-1967 impl");
    }
}
