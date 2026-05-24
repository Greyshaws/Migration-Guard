// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {AdminOwnerInApprovedSet} from "../src/properties/AdminOwnerInApprovedSet.sol";
import {TxOriginInAuthorization} from "../src/properties/TxOriginInAuthorization.sol";
import {OracleDecimalConsistency} from "../src/properties/OracleDecimalConsistency.sol";
import {StorageLayoutCompatibility} from "../src/properties/StorageLayoutCompatibility.sol";
import {DeadSelectorEnumerator} from "../src/properties/DeadSelectorEnumerator.sol";
import {LiquidityDecayInvariant} from "../src/properties/LiquidityDecayInvariant.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

contract RunAll is Script {
    AdminOwnerInApprovedSet ownerCheck;
    TxOriginInAuthorization originCheck;
    OracleDecimalConsistency oracleCheck;
    StorageLayoutCompatibility storageCheck;
    DeadSelectorEnumerator deadCheck;
    LiquidityDecayInvariant liqCheck;

    function setUp() public {
        ownerCheck = new AdminOwnerInApprovedSet();
        originCheck = new TxOriginInAuthorization();
        oracleCheck = new OracleDecimalConsistency();
        storageCheck = new StorageLayoutCompatibility();
        deadCheck = new DeadSelectorEnumerator();
        liqCheck = new LiquidityDecayInvariant();
        vm.makePersistent(address(ownerCheck));
        vm.makePersistent(address(originCheck));
        vm.makePersistent(address(oracleCheck));
        vm.makePersistent(address(storageCheck));
        vm.makePersistent(address(deadCheck));
        vm.makePersistent(address(liqCheck));
    }

    function run() external {
        // ---- Load config from env ----
        address adminAddr   = vm.envAddress("UG_ADMIN_ADDRESS");
        uint256 slotNum     = vm.envUint("UG_OWNER_SLOT");
        bytes32 ownerSlot   = bytes32(slotNum);
        bool ownerEnabled   = vm.envBool("UG_OWNER_CHECK_ENABLED");
        bool originEnabled  = vm.envBool("UG_ORIGIN_CHECK_ENABLED");
        bool oracleEnabled  = vm.envBool("UG_ORACLE_CHECK_ENABLED");
        bool storageEnabled = vm.envBool("UG_STORAGE_CHECK_ENABLED");
        bool deadEnabled    = vm.envBool("UG_DEAD_CHECK_ENABLED");
        bool liqEnabled     = vm.envBool("UG_LIQ_CHECK_ENABLED");

        address[] memory approved = _parseApprovedOwners();
        uint256 failures = 0;

        console.log("");
        console.log("Target:");
        console.log("  ", adminAddr);
        console.log("Block:", block.number);
        console.log("");
        console.log("-------------------------------------------");
        console.log("Property results");
        console.log("-------------------------------------------");

        if (ownerEnabled) {
            PropertyResult memory r = ownerCheck.check(adminAddr, ownerSlot, approved);
            _printResult("auth.OwnerCheck", r);
            if (!r.ok) failures++;
        }

        if (originEnabled) {
            PropertyResult memory r = originCheck.check(adminAddr);
            _printResult("auth.DetectTxOrigin", r);
            if (!r.ok) failures++;
        }

        if (oracleEnabled) {
            address oracleAddr   = vm.envAddress("UG_ORACLE_ADDRESS");
            address consumerAddr = vm.envAddress("UG_ORACLE_CONSUMER");
            uint256 expDec       = vm.envUint("UG_ORACLE_EXPECTED_DECIMALS");
            PropertyResult memory r = oracleCheck.check(oracleAddr, consumerAddr, uint8(expDec));
            _printResult("scaling.MatchOracleDecimals", r);
            if (!r.ok) failures++;
        }

        if (storageEnabled) {
            uint256 initSlotNum = vm.envUint("UG_STORAGE_INITIALIZED_SLOT");
            bytes32 initSlot = bytes32(initSlotNum);
            address[] memory approvedImpls = _parseAddressCsv("UG_STORAGE_APPROVED_IMPLS_CSV");
            PropertyResult memory r = storageCheck.check(adminAddr, initSlot, approvedImpls);
            _printResult("storage.ProxyStateCheck", r);
            if (!r.ok) failures++;
        }

        if (deadEnabled) {
            bytes4[] memory deadSels = _parseSelectorCsv("UG_DEAD_SELECTORS_CSV");
            PropertyResult memory r = deadCheck.check(adminAddr, deadSels);
            _printResult("surface.FindLiveSelectors", r);
            if (!r.ok) failures++;
        }

        if (liqEnabled) {
            address legacyAsset   = vm.envAddress("UG_LIQ_LEGACY_ASSET");
            address oracleSource  = vm.envAddress("UG_LIQ_ORACLE_SOURCE");
            uint256 safetyRatio   = vm.envUint("UG_LIQ_SAFETY_RATIO");
            PropertyResult memory r = liqCheck.check(adminAddr, legacyAsset, oracleSource, safetyRatio);
            _printResult("liquidity.PoolDepthCheck", r);
            if (!r.ok) failures++;
        }

        console.log("===========================================");
        console.log("Summary");
        console.log("===========================================");
        if (failures == 0) {
            console.log("STATUS: PASS - all checks passed");
        } else {
            console.log("STATUS: FAIL");
            console.log("Failures:", failures);
            console.log("");
            console.log("DO NOT MERGE / DO NOT DEPLOY");
        }
    }

    function _parseApprovedOwners() internal view returns (address[] memory) {
        return _parseAddressCsv("UG_APPROVED_OWNERS_CSV");
    }

    function _parseAddressCsv(string memory envVar) internal view returns (address[] memory) {
        string memory csv = vm.envString(envVar);
        bytes memory raw = bytes(csv);

        if (raw.length == 0) return new address[](0);

        uint256 count = 1;
        for (uint256 i = 0; i < raw.length; i++) {
            if (raw[i] == ',') count++;
        }
        address[] memory result = new address[](count);
        uint256 start = 0;
        uint256 idx = 0;
        for (uint256 i = 0; i <= raw.length; i++) {
            if (i == raw.length || raw[i] == ',') {
                bytes memory segment = new bytes(i - start);
                for (uint256 j = 0; j < segment.length; j++) {
                    segment[j] = raw[start + j];
                }
                result[idx++] = vm.parseAddress(string(segment));
                start = i + 1;
            }
        }
        return result;
    }

    function _parseSelectorCsv(string memory envVar) internal view returns (bytes4[] memory) {
        string memory csv = vm.envString(envVar);
        bytes memory raw = bytes(csv);

        if (raw.length == 0) return new bytes4[](0);

        uint256 count = 1;
        for (uint256 i = 0; i < raw.length; i++) {
            if (raw[i] == ',') count++;
        }
        bytes4[] memory result = new bytes4[](count);
        uint256 start = 0;
        uint256 idx = 0;
        for (uint256 i = 0; i <= raw.length; i++) {
            if (i == raw.length || raw[i] == ',') {
                bytes memory segment = new bytes(i - start);
                for (uint256 j = 0; j < segment.length; j++) {
                    segment[j] = raw[start + j];
                }
                result[idx++] = bytes4(vm.parseBytes(string(segment)));
                start = i + 1;
            }
        }
        return result;
    }

    function _printResult(string memory id, PropertyResult memory r) internal pure {
        console.log("");
        console.log(id);
        if (r.ok) {
            console.log("  Status:    PASS");
        } else {
            console.log("  Status:    FAIL");
            console.log("  Severity:  ", _sev(r.severity));
            console.log("  Reason:    ", r.reason);
        }
    }

    function _sev(Severity s) internal pure returns (string memory) {
        if (s == Severity.CRITICAL) return "CRITICAL";
        if (s == Severity.HIGH)     return "HIGH";
        if (s == Severity.MEDIUM)   return "MEDIUM";
        if (s == Severity.LOW)      return "LOW";
        return "INFO";
    }
}
