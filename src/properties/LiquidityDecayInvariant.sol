// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IMigrationProperty, PropertyResult, Severity} from "../IMigrationProperty.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @notice Verifies that the liquidity of an oracle's underlying source is
///         sufficient relative to the legacy contract's exposure.
///
/// Catches the liquidity-decay class of bug:
///   - Yearn V1 (Dec 2025): legacy vaults still active long after V2 launch;
///     as TVL migrated to V2, the AMM pools their oracles relied on became
///     thin enough that flash-loan attacks became profitable.
///   - Polter Finance (Nov 2024): oracle manipulation via thin BOO/USDC pool
///     allowed inflation of collateral value to absurd levels.
///   - Huma V1 (May 2026): similar pattern on Polygon.
///
/// How the check works:
///   - Reads the legacy contract's balance of its primary asset (its TVL).
///   - Reads the liquidity in the oracle source (typically a DEX pool's
///     reserves in the same asset).
///   - Fails if oracle liquidity < legacy TVL * safetyRatio.
///
/// Limitations (honest scope):
///   - "Liquidity sufficient" is a heuristic, not a proof. A 3x ratio is a
///     reasonable rule of thumb but doesn't guarantee resistance to all
///     manipulation strategies (multi-hop, multi-block, etc.).
///   - Production version would compute actual flash-loan-attack cost
///     and compare to attack-profitable threshold.
///   - The check assumes the legacy contract and oracle source hold the same
///     asset (e.g., both denominated in USDC). Cross-asset comparisons need
///     a price feed of their own.
contract LiquidityDecayInvariant is IMigrationProperty, Test {
    function id() external pure override returns (string memory) {
        return "liquidity.PoolDepthCheck";
    }

    function category() external pure override returns (string memory) {
        return "LIQUIDITY";
    }

    /// @param legacyContract     The legacy contract holding user funds
    /// @param legacyAsset        The ERC20 the legacy contract holds (its TVL asset)
    /// @param oracleSource       The DEX pool / liquidity source the oracle reads from
    /// @param safetyRatio        Required ratio: oracle_liquidity >= legacy_tvl * safetyRatio
    ///                           Expressed as basis points (10000 = 1x, 30000 = 3x).
    /// @return result            Pass/fail with the measured values
    function check(
        address legacyContract,
        address legacyAsset,
        address oracleSource,
        uint256 safetyRatio
    ) external view returns (PropertyResult memory result) {
        // All three addresses must be deployed contracts
        if (_codeSize(legacyContract) == 0) {
            return _fail("Legacy contract has no code", legacyContract);
        }
        if (_codeSize(legacyAsset) == 0) {
            return _fail("Legacy asset has no code", legacyAsset);
        }
        if (_codeSize(oracleSource) == 0) {
            return _fail("Oracle source has no code", oracleSource);
        }

        // Read TVL of legacy contract in its primary asset.
        uint256 legacyTvl = IERC20(legacyAsset).balanceOf(legacyContract);

        // Read liquidity of the oracle source in the same asset.
        uint256 oracleLiquidity = IERC20(legacyAsset).balanceOf(oracleSource);

        // Required liquidity = legacyTvl * safetyRatio / 10000
        uint256 requiredLiquidity = (legacyTvl * safetyRatio) / 10000;

        if (oracleLiquidity < requiredLiquidity) {
            return PropertyResult({
                ok: false,
                reason: "Oracle source liquidity below safety threshold relative to legacy TVL",
                severity: Severity.HIGH,
                evidence: abi.encode(
                    legacyContract,
                    oracleSource,
                    legacyTvl,
                    oracleLiquidity,
                    requiredLiquidity
                )
            });
        }

        return PropertyResult({
            ok: true,
            reason: "",
            severity: Severity.INFO,
            evidence: abi.encode(legacyContract, oracleSource, legacyTvl, oracleLiquidity)
        });
    }

    function _codeSize(address a) internal view returns (uint256 size) {
        assembly { size := extcodesize(a) }
    }

    function _fail(string memory reason, address subject) internal pure returns (PropertyResult memory) {
        return PropertyResult({
            ok: false,
            reason: reason,
            severity: Severity.CRITICAL,
            evidence: abi.encode(subject)
        });
    }
}
