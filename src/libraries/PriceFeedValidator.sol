// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title PriceFeedValidator
/// @notice Library for validating Chainlink price feed data
library PriceFeedValidator {
    /// @dev Maximum age of price feed data (1 hour)
    uint256 private constant PRICE_FEED_MAX_AGE = 3600;

    error PRICE_FEED__StalePrice();
    error PRICE_FEED__InvalidPrice();
    error PRICE_FEED__InconsistentRound();

    /// @notice Validates price feed data and returns normalized price
    /// @param priceFeed The Chainlink price feed to validate
    /// @return price The normalized price with 18 decimals
    function validateAndGetPrice(AggregatorV3Interface priceFeed) internal view returns (uint256 price) {
        (
            uint80 roundId,
            int256 answer,
            ,  // startedAt (unused)
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        // Check for stale price
        if (block.timestamp - updatedAt > PRICE_FEED_MAX_AGE) {
            revert PRICE_FEED__StalePrice();
        }
        
        // Check for invalid price
        if (answer <= 0) {
            revert PRICE_FEED__InvalidPrice();
        }

        // Check for round consistency
        if (answeredInRound < roundId) {
            revert PRICE_FEED__InconsistentRound();
        }
        
        // Normalize price to 18 decimals
        uint8 decimals = priceFeed.decimals();
        return uint256(answer) * (10 ** uint256(18 - decimals));
    }
} 