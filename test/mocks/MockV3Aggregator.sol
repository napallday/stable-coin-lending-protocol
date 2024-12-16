// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockV3Aggregator
 * @notice Based on the FluxAggregator contract
 * @notice Use this contract when you need to test
 * other contract's ability to read data from an
 * aggregator contract, but how the aggregator got
 * its answer is unimportant
 */
contract MockV3Aggregator {
    uint8 public decimals;
    int256 private s_answer;
    uint80 private s_roundId;
    uint256 private s_timestamp;
    uint80 private s_answeredInRound;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimals = _decimals;
        s_answer = _initialAnswer;
        s_roundId = 1;
        s_timestamp = block.timestamp;
        s_answeredInRound = 1;
    }

    function updateAnswer(int256 _answer) external {
        s_roundId++;
        s_answer = _answer;
        s_timestamp = block.timestamp;
        s_answeredInRound = s_roundId;
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint80 _answeredInRound
    ) external {
        s_roundId = _roundId;
        s_answer = _answer;
        s_timestamp = block.timestamp;
        s_answeredInRound = _answeredInRound;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            s_roundId,
            s_answer,
            s_timestamp,
            s_timestamp,
            s_answeredInRound
        );
    }

    function description() external pure returns (string memory) {
        return "v0.8/tests/MockV3Aggregator.sol";
    }
}
