// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {SCoin} from "../src/SCoin.sol";
import {Hub} from "../src/Hub.sol";

contract Deploy is Script {
    address[] public supportedTokenAddresses;
    address[] public priceFeeds;

    function run() external returns (SCoin, Hub, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address weth, address wbtc, address wethUsdPriceFeed, address wbtcUsdPriceFeed) = helperConfig.networkConfig();
        supportedTokenAddresses = [weth, wbtc];
        priceFeeds = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast();
        SCoin scoin = new SCoin();
        Hub hub = new Hub(address(scoin), supportedTokenAddresses, priceFeeds);
        vm.stopBroadcast();

        return (scoin, hub, helperConfig);
    }
}
