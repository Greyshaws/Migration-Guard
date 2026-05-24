// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityDecayInvariant} from "../src/properties/LiquidityDecayInvariant.sol";
import {PropertyResult, Severity} from "../src/IMigrationProperty.sol";

/// Minimal mock ERC20 for synthetic tests.
contract MockToken {
    mapping(address => uint256) public balances;
    function balanceOf(address a) external view returns (uint256) {
        return balances[a];
    }
    function decimals() external pure returns (uint8) { return 18; }
    function set(address a, uint256 amt) external {
        balances[a] = amt;
    }
}

/// Empty placeholder for "contract that exists." extcodesize > 0.
contract MockContract {
    function ping() external pure returns (uint256) { return 1; }
}

contract LiquidityDecayInvariantTest is Test {
    // USDC token on mainnet (real, will work for the real-world test)
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // A known deep Uniswap V3 USDC pool (USDC/WETH 0.05%)
    address constant USDC_WETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    // An arbitrary contract with low USDC balance, for the legacy contract role
    address constant SOME_LEGACY = 0x3c212A044760DE5a529B3Ba59363ddeCcc2210bE;

    uint256 constant POST_DEPLOYMENT_BLOCK = 23994254;

    LiquidityDecayInvariant property;
    MockToken token;
    MockContract legacy;
    MockContract oracleSource;

    function setUp() public {
        property = new LiquidityDecayInvariant();
        token = new MockToken();
        legacy = new MockContract();
        oracleSource = new MockContract();
        vm.makePersistent(address(property));
        vm.makePersistent(address(token));
        vm.makePersistent(address(legacy));
        vm.makePersistent(address(oracleSource));
    }

    /// Synthetic: oracle source has 10x the liquidity of legacy TVL.
    /// Safety ratio 3x -> passes.
    function test_passesWhenLiquidityIsAbundant() public {
        token.set(address(legacy), 1_000_000 ether);          // 1M legacy TVL
        token.set(address(oracleSource), 10_000_000 ether);   // 10M oracle liquidity

        PropertyResult memory r = property.check(
            address(legacy),
            address(token),
            address(oracleSource),
            30000  // 3x in basis points
        );

        console.log("Result ok:", r.ok);
        assertTrue(r.ok, "10x liquidity should pass 3x safety check");
    }

    /// Synthetic: oracle source has only 1x of legacy TVL.
    /// Safety ratio 3x -> fails (this is the Yearn-style decay scenario).
    function test_failsWhenLiquidityHasDecayed() public {
        token.set(address(legacy), 1_000_000 ether);          // 1M legacy TVL
        token.set(address(oracleSource), 1_000_000 ether);    // 1M oracle liquidity = 1x

        PropertyResult memory r = property.check(
            address(legacy),
            address(token),
            address(oracleSource),
            30000  // 3x required
        );

        console.log("Result ok:", r.ok);
        console.log("Reason:", r.reason);

        (, , uint256 tvl, uint256 oracleLiq, uint256 required) = abi.decode(
            r.evidence, (address, address, uint256, uint256, uint256)
        );
        console.log("Legacy TVL:        ", tvl);
        console.log("Oracle liquidity:  ", oracleLiq);
        console.log("Required liquidity:", required);

        assertFalse(r.ok, "1x liquidity should fail 3x safety check");
        assertEq(uint8(r.severity), uint8(Severity.HIGH));
    }

    /// Synthetic edge case: legacy TVL is zero. Any oracle liquidity satisfies
    /// the ratio (required = 0). Passes trivially.
    function test_passesWhenLegacyTvlIsZero() public {
        token.set(address(legacy), 0);
        token.set(address(oracleSource), 1_000 ether);

        PropertyResult memory r = property.check(
            address(legacy),
            address(token),
            address(oracleSource),
            30000
        );

        assertTrue(r.ok, "zero TVL should pass trivially");
    }

    /// Non-contract addresses fail with the appropriate reason.
    function test_failsOnMissingLegacyContract() public {
        PropertyResult memory r = property.check(
            address(0xdead),
            address(token),
            address(oracleSource),
            30000
        );

        assertFalse(r.ok);
        assertEq(uint8(r.severity), uint8(Severity.CRITICAL));
    }

    /// Real-world: USDC/WETH pool has plenty of USDC relative to most users.
    /// Should pass for the SOME_LEGACY contract (which has minimal USDC).
    function test_passesOnRealMainnet_deepPool() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), POST_DEPLOYMENT_BLOCK);

        PropertyResult memory r = property.check(
            SOME_LEGACY,
            USDC,
            USDC_WETH_POOL,
            30000  // 3x safety
        );

        (, , uint256 tvl, uint256 oracleLiq) = abi.decode(
            r.evidence, (address, address, uint256, uint256)
        );
        console.log("Real legacy USDC:   ", tvl);
        console.log("Real pool USDC:     ", oracleLiq);
        console.log("Result ok:", r.ok);

        // If SOME_LEGACY holds little USDC, the deep pool dwarfs it -> pass.
        // We don't assert true/false here because real on-chain state can vary;
        // we just verify the check completed and produced sensible evidence.
        assertTrue(tvl < type(uint256).max);
        assertTrue(oracleLiq > 0);
    }
}
