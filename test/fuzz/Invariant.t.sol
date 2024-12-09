// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Hub} from "../../src/Hub.sol";
import {SCoin} from "../../src/SCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./handler.t.sol";
import {console} from "forge-std/console.sol";

/// @title Invariant Tests for Hub Contract
/// @notice Tests invariant properties of the Hub system
/// @dev Uses Handler contract to generate fuzz test cases
contract InvariantTest is StdInvariant, Test {
    Hub public hub;
    SCoin public scoin;
    HelperConfig public config;
    Handler public handler;

    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;

    /// @notice Sets up the invariant test environment
    /// @dev Deploys contracts and configures the handler
    function setUp() external {
        Deploy deployer = new Deploy();
        (scoin, hub, config) = deployer.run();
        (weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed) = config.networkConfig();
        handler = new Handler(hub, scoin);
        targetContract(address(handler));
    }

    /// @notice Tests that total sCoin supply never exceeds half of total collateral value
    /// @dev This is a critical system invariant for maintaining solvency
    function invariant_totalSupplyShouldBeLessThanHalfCollateralValue() public view {
        // Get total supply of sCoin
        uint256 totalSupply = scoin.totalSupply();

        // Calculate total collateral value in USD
        uint256 totalCollateralValueInUsd;

        // Get WETH collateral value
        uint256 wethBalance = IERC20(weth).balanceOf(address(hub));
        totalCollateralValueInUsd += hub.getTokenValueInUSD(weth, wethBalance);

        // Get WBTC collateral value
        uint256 wbtcBalance = IERC20(wbtc).balanceOf(address(hub));
        totalCollateralValueInUsd += hub.getTokenValueInUSD(wbtc, wbtcBalance);

        // Total supply should be less than half of total collateral value
        // This is because the minimum health factor is 1e18 (100%)
        // And liquidation threshold is 50%
        assert(totalSupply <= (totalCollateralValueInUsd * 1e18) / 2);
    }
}
