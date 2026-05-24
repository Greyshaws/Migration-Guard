// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AdminOwnerInApprovedSet} from "../src/properties/AdminOwnerInApprovedSet.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

contract AdminOwnerInApprovedSetTest is Test {
    // ---- Aevo case constants ----
    address constant PROXY_OWNER = 0x9D7b3586f361e3621Bf4F099cBC9d155e8ae6B76;
    address constant FALL_GUY    = 0xB594F7e7Ad548F63dB49665ae4e3D3F8457CF6f5;
    bytes32 constant OWNER_SLOT  = bytes32(uint256(0));

    uint256 constant BLOCK_PRE_DEPLOYMENT  = 23950000;  // contract didn't exist
    uint256 constant BLOCK_POST_DEPLOYMENT = 23994254;  // contract exists, owner = Fall Guy
    uint256 constant BLOCK_AT_EXPLOIT      = 23995254;

    // Approved set: in reality, the Aevo team's multisig. We don't have its
    // address handy, so we use a placeholder for demo purposes. The test still
    // proves the property correctly identifies the Fall Guy as NOT in the set.
    address constant AEVO_LEGITIMATE_MULTISIG = 0x0000000000000000000000000000000000000001;

    AdminOwnerInApprovedSet property;

    function setUp() public {
        property = new AdminOwnerInApprovedSet();
        vm.makePersistent(address(property));
   }

    /// At a block before deployment, the property should fail with "no code".
    function test_failsWhenContractNotDeployed() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_PRE_DEPLOYMENT);

        address[] memory approved = new address[](1);
        approved[0] = AEVO_LEGITIMATE_MULTISIG;

        PropertyResult memory r = property.check(PROXY_OWNER, OWNER_SLOT, approved);

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        assertFalse(r.ok, "should fail when contract has no code");
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }

    /// At the exploit block, the owner is the Fall Guy — not in the approved
    /// set. The property should fail with "not in approved set".
    function test_failsAtExploitBlock_ownerIsAttacker() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_POST_DEPLOYMENT);

        address[] memory approved = new address[](1);
        approved[0] = AEVO_LEGITIMATE_MULTISIG;

        PropertyResult memory r = property.check(PROXY_OWNER, OWNER_SLOT, approved);

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);
        // Decode evidence to confirm we caught the Fall Guy
        (, , address ownerFound, ) = abi.decode(r.evidence, (address, bytes32, address, address[]));
        console.log("Owner found:", ownerFound);

        assertFalse(r.ok, "should fail at exploit block");
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
        assertEq(ownerFound, FALL_GUY, "should identify the Fall Guy as the unauthorized owner");
    }

    /// Sanity check: when we include the Fall Guy in the approved set,
    /// the property passes. Proves the check isn't just "always fail."
    function test_passesWhenAttackerIsInApprovedSet() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_POST_DEPLOYMENT);

        address[] memory approved = new address[](1);
        approved[0] = FALL_GUY;  // not what you'd do in production, but proves logic

        PropertyResult memory r = property.check(PROXY_OWNER, OWNER_SLOT, approved);

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "should pass when Fall Guy is in approved set");
    }
}