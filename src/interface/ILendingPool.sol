// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ILendingPool {
    function depositAndMint(address collateralAddress, uint256 amountCollateral, uint256 amountSCoin) external;

    function redeemAndBurn(address collateralAddress, uint256 amountCollateral, uint256 amountSCoin) external;

    function redeem(address collateralAddress, uint256 amountCollateral) external;

    function burn(uint256 amountSCoin) external;

    function liquidate(address user, address colleralAddress, uint256 repayAmount) external;

    function getHealthFactor(address user) external view returns (uint256);
}
