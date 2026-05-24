// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

contract Day1Smoke is Test {
    uint256 constant BLOCK_AFTER_UPGRADE  = 23994254;
    uint256 constant EXPLOIT_BLOCK        = 23995254;
    uint256 constant DRAIN_BLOCK          = 23995264;

    address constant PROXY_OWNER  = 0x9D7b3586f361e3621Bf4F099cBC9d155e8ae6B76;
    address constant VICTIM_VAULT = 0x3c212A044760DE5a529B3Ba59363ddeCcc2210bE;

    // From bytecode analysis of unverified contract at PROXY_OWNER:
    // Selector 0x31c9d4a4 returns the owner address (reads storage slot 0).
    bytes4 constant SEL_PROXY_OWNER = 0x31c9d4a4;
    // Selector 0xb8a7a8e2 returns secondary address (reads storage slot 1).
    bytes4 constant SEL_SECONDARY = 0xb8a7a8e2;
    // Selector 0x460becc7 takes an address and returns its authorized bool.
    bytes4 constant SEL_IS_AUTHORIZED = 0x460becc7;

    function test_canReadProxyOwnerAfterUpgrade() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), BLOCK_AFTER_UPGRADE);

        // Verify the contract exists at this block
        uint256 codeSize;
        address target = PROXY_OWNER;
        assembly { codeSize := extcodesize(target) }
        console.log("ProxyOwner code size:", codeSize);
        assertGt(codeSize, 0, "ProxyOwner should have code at this block");

        // Read owner via raw selector call
        (bool ok, bytes memory data) = PROXY_OWNER.staticcall(abi.encodeWithSelector(SEL_PROXY_OWNER));
        assertTrue(ok, "owner getter call should succeed");
        address owner = abi.decode(data, (address));
        console.log("ProxyOwner owner:", owner);

        // Read secondary slot
        (ok, data) = PROXY_OWNER.staticcall(abi.encodeWithSelector(SEL_SECONDARY));
        assertTrue(ok, "secondary getter call should succeed");
        address secondary = abi.decode(data, (address));
        console.log("ProxyOwner secondary:", secondary);
    }

    function test_canReadVaultAtExploitBlock() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), EXPLOIT_BLOCK - 1);

        uint256 codeSize;
        address target = VICTIM_VAULT;
        assembly { codeSize := extcodesize(target) }
        console.log("Victim vault code size:", codeSize);
        assertGt(codeSize, 0, "Victim vault should have code at exploit-1 block");
    }

    function test_ownerAcrossExploitBlocks() public {
        bytes4 SEL_PROXY_OWNER = 0x31c9d4a4;
    
        // Just before the exploit
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), EXPLOIT_BLOCK - 1);
        (bool ok1, bytes memory data1) = PROXY_OWNER.staticcall(abi.encodeWithSelector(SEL_PROXY_OWNER));
        require(ok1, "call failed at exploit-1");
        address ownerBeforeExploit = abi.decode(data1, (address));
        console.log("Owner at exploit_block - 1:", ownerBeforeExploit);
    
        // At the drain block (or just after)
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), DRAIN_BLOCK + 10);
        (bool ok2, bytes memory data2) = PROXY_OWNER.staticcall(abi.encodeWithSelector(SEL_PROXY_OWNER));
        require(ok2, "call failed at drain+10");
        address ownerAfterDrain = abi.decode(data2, (address));
        console.log("Owner at drain_block + 10:", ownerAfterDrain);
    }
}