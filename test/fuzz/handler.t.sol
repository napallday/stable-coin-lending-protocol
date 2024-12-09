// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Hub} from "../../src/Hub.sol";
import {SCoin} from "../../src/SCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {console} from "forge-std/console.sol";

/// @title Handler Contract for Fuzz Testing
/// @notice Manages fuzz test interactions with the Hub contract
/// @dev Used by the invariant tests to generate random but valid test cases
contract Handler is Test {
    Hub public hub;
    SCoin public scoin;
    HelperConfig public config;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    MockV3Aggregator public wethUsdPriceFeed;
    MockV3Aggregator public wbtcUsdPriceFeed;
    uint256 public constant MAX_COLLATERAL_AMOUNT = type(uint80).max;
    uint256 public constant MAX_DEBT_TO_COVER = type(uint80).max;
    address[] public users;
    mapping(address user => bool existed) public userExisted;

    /// @notice Initializes the handler with Hub and SCoin contract instances
    /// @param _hub The Hub contract instance
    /// @param _scoin The SCoin contract instance
    constructor(Hub _hub, SCoin _scoin) {
        hub = _hub;
        scoin = _scoin;
        weth = ERC20Mock(hub.s_supportedCollateralTokens(0));
        wbtc = ERC20Mock(hub.s_supportedCollateralTokens(1));
        wethUsdPriceFeed = MockV3Aggregator(hub.s_priceFeeds(address(weth)));
        wbtcUsdPriceFeed = MockV3Aggregator(hub.s_priceFeeds(address(wbtc)));
    }

    /// @notice Handles deposit operations for fuzz testing
    /// @param _collateralType Type of collateral (0 for WETH, 1 for WBTC)
    /// @param _amount Amount to deposit (bounded by MAX_COLLATERAL_AMOUNT)
    function deposit(uint8 _collateralType, uint256 _amount) public {
        _amount = bound(_amount, 1, MAX_COLLATERAL_AMOUNT);
        ERC20Mock collateralAddress = _getCollateralAddress(_collateralType);
        vm.startPrank(msg.sender);
        collateralAddress.mint(msg.sender, _amount);
        collateralAddress.approve(address(hub), _amount);
        hub.deposit(address(collateralAddress), _amount);
        vm.stopPrank();
        if (!userExisted[msg.sender]) {
            users.push(msg.sender);
            userExisted[msg.sender] = true;
        }
    }

    /// @notice Handles redeem operations for fuzz testing
    /// @param _collateralType Type of collateral to redeem
    /// @param _redeemAmount Amount to redeem (bounded by user's balance)
    function redeem(uint8 _collateralType, uint256 _redeemAmount) public {
        ERC20Mock collateralAddress = _getCollateralAddress(_collateralType);
        uint256 collateralAmount = hub.getCollateralAmountForUser(msg.sender, address(collateralAddress));
        _redeemAmount = bound(_redeemAmount, 0, collateralAmount);
        vm.assume(_redeemAmount > 0);
        
        vm.startPrank(msg.sender);
        hub.redeem(address(collateralAddress), _redeemAmount);
        vm.stopPrank();
    }

    /// @notice Handles minting operations for fuzz testing
    /// @param _mintAmount Amount of sCoin to mint
    /// @dev Ensures minting amount respects collateral ratio and health factor
    function mint(uint256 _mintAmount) public {
        uint256 scoinBalance = scoin.balanceOf(msg.sender);
        uint256 collateralValue = hub.getCollateralValueInUSDForUser(msg.sender);
        vm.assume(collateralValue > 0);
        vm.assume(collateralValue / 2 > scoinBalance);

        uint256 maxMintable = collateralValue / 2 - scoinBalance;
        _mintAmount = bound(_mintAmount, 0, maxMintable);
        vm.assume(_mintAmount > 0);

        vm.startPrank(msg.sender);
        scoin.mint(msg.sender, _mintAmount);
        vm.stopPrank();
    }

    /// @notice Handles burning operations for fuzz testing
    /// @param _burnAmount Amount of sCoin to burn
    /// @dev Ensures burn amount doesn't exceed user's balance
    function burn(uint256 _burnAmount) public {
        uint256 scoinBalance = scoin.balanceOf(msg.sender);
        _burnAmount = bound(_burnAmount, 0, scoinBalance);
        vm.assume(_burnAmount > 0);

        vm.startPrank(msg.sender);
        scoin.burn(msg.sender, _burnAmount);
        vm.stopPrank();
    }

    /// @notice Handles liquidation operations for fuzz testing
    /// @param _collateralType Type of collateral to liquidate (0 for WETH, 1 for WBTC)
    /// @param _userSeed Random seed to select a user to liquidate
    /// @param _debtToCover Amount of debt to cover in the liquidation
    /// @dev Only liquidates users with health factor below minimum threshold
    function liquidate(uint8 _collateralType, uint256 _userSeed, uint256 _debtToCover) public {
        uint256 minHealthFactor = hub.getMinHealthFactor();

        vm.assume(users.length > 0);
        address user = users[_userSeed % users.length];

        uint256 currentHealthFactor = hub.getHealthFactor(user);
        vm.assume(currentHealthFactor < minHealthFactor);

        _debtToCover = bound(_debtToCover, 1, MAX_DEBT_TO_COVER);

        vm.startPrank(msg.sender);
        hub.liquidate(user, address(_getCollateralAddress(_collateralType)), _debtToCover);
        vm.stopPrank();
    }

    /// @notice Helper function to get the collateral token address based on type
    /// @param _collateralType Type of collateral (0 for WETH, 1 for WBTC)
    /// @return ERC20Mock The address of the collateral token
    /// @dev Uses modulo to ensure valid collateral type even with random input
    function _getCollateralAddress(uint8 _collateralType) internal view returns (ERC20Mock) {
        return _collateralType % 2 == 0 ? weth : wbtc;
    }
}
