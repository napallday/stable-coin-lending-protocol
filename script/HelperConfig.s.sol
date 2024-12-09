// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_WETH_PRICE = 4000e8;
    int256 public constant INITIAL_WBTC_PRICE = 90000e8;

    struct NetworkConfig {
        address weth;
        address wbtc;
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
    }

    NetworkConfig public networkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            networkConfig = getSepoliaConfig();
        } else {
            networkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() private pure returns (NetworkConfig memory) {
        // from https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
        return NetworkConfig({
            weth: address(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14),
            wbtc: address(0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43),
            wethUsdPriceFeed: address(0x694AA1769357215DE4FAC081bf1f309aDC325306),
            wbtcUsdPriceFeed: address(0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43)
        });
    }

    function getAnvilConfig() private returns (NetworkConfig memory) {
        vm.startBroadcast();
        ERC20Mock weth = new ERC20Mock();
        ERC20Mock wbtc = new ERC20Mock();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_WETH_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_WBTC_PRICE);
        vm.stopBroadcast();

        return NetworkConfig({
            weth: address(weth),
            wbtc: address(wbtc),
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed)
        });
    }
}
