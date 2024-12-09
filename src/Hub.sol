// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {SCoin} from "./SCoin.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Hub {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HUB__LengthNotMatch();
    error HUB__CollateralTokenNotSupported();
    error HUB__TransferFailed();
    error HUB__HealthFactorTooLow();
    error HUB__HealthFactorEnough();
    error HUB__NotEnoughCollateral();
    error HUB__AmountMustBeMoreThanZero();
    /*//////////////////////////////////////////////////////////////
                         CONSTANT AND IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    SCoin private immutable i_sCoin;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_MAX_BONUS_THRESHOLD = 110e16;
    uint256 private constant HEALTH_FACTOR_THRESHOLD = 1e18;
    uint256 private constant BONUS = 10;
    uint256 private constant BONUS_PRECISION = 100;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address[] public s_supportedCollateralTokens;
    mapping(address collateralToken => address priceFeed) public s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 tokenAmount)) private s_collateralBalances;
    mapping(address user => uint256 scoinAmount) private s_sCoinBalances;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposit(address indexed user, address indexed collateralToken, uint256 amountCollateral);
    event CollateralRedeem(
        address indexed redeemFrom, address indexed redeemTo, address indexed collateralToken, uint256 amountCollateral
    );
    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier checkCollateralTokenSupported(address _collateralToken) {
        if (s_priceFeeds[_collateralToken] == address(0)) {
            revert HUB__CollateralTokenNotSupported();
        }
        _;
    }

    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert HUB__AmountMustBeMoreThanZero();
        }
        _;
    }
    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _sCoinAddress, address[] memory _supportedCollateralTokens, address[] memory _priceFeeds) {
        if (_supportedCollateralTokens.length != _priceFeeds.length) {
            revert HUB__LengthNotMatch();
        }
        i_sCoin = SCoin(_sCoinAddress);
        s_supportedCollateralTokens = _supportedCollateralTokens;
        for (uint256 i = 0; i < _supportedCollateralTokens.length; i++) {
            require(s_priceFeeds[_supportedCollateralTokens[i]] == address(0), "Collateral token was already set");
            s_priceFeeds[_supportedCollateralTokens[i]] = _priceFeeds[i];
        }
    }

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Deposits collateral and mints sCoin in a single transaction
    /// @param _collateralToken The address of the collateral token to deposit
    /// @param _amountCollateral The amount of collateral to deposit
    /// @param _amountSCoin The amount of sCoin to mint
    function depositAndMint(address _collateralToken, uint256 _amountCollateral, uint256 _amountSCoin)
        public
        checkCollateralTokenSupported(_collateralToken)
        moreThanZero(_amountCollateral)
    {
        // Transfer collateral token from user to this contract
        bool success = IERC20(_collateralToken).transferFrom(msg.sender, address(this), _amountCollateral);
        if (!success) {
            revert HUB__TransferFailed();
        }
        // Update collateral balance
        s_collateralBalances[msg.sender][_collateralToken] += _amountCollateral;
        emit CollateralDeposit(msg.sender, _collateralToken, _amountCollateral);
        // Mint sCoin to user
        i_sCoin.mint(msg.sender, _amountSCoin);
        // Update sCoin balance
        s_sCoinBalances[msg.sender] += _amountSCoin;
        _checkHealthFactor(msg.sender);
    }

    /// @notice Deposits collateral without minting any sCoin
    /// @param _collateralToken The address of the collateral token to deposit
    /// @param _amountCollateral The amount of collateral to deposit
    function deposit(address _collateralToken, uint256 _amountCollateral)
        external
        checkCollateralTokenSupported(_collateralToken)
        moreThanZero(_amountCollateral)
    {
        depositAndMint(_collateralToken, _amountCollateral, 0);
    }

    /// @notice Mints new sCoin tokens to the caller
    /// @param _amountSCoin The amount of sCoin to mint
    function mint(uint256 _amountSCoin) external moreThanZero(_amountSCoin) {
        i_sCoin.mint(msg.sender, _amountSCoin);
        s_sCoinBalances[msg.sender] += _amountSCoin;
        _checkHealthFactor(msg.sender);
    }

    /// @notice Redeems collateral and burns sCoin in a single transaction
    /// @param _collateralToken The address of the collateral token to redeem
    /// @param _amountCollateral The amount of collateral to redeem
    /// @param _amountSCoin The amount of sCoin to burn
    function redeemAndBurn(address _collateralToken, uint256 _amountCollateral, uint256 _amountSCoin)
        public
        checkCollateralTokenSupported(_collateralToken)
    {
        _redeemAndBurn(_collateralToken, _amountCollateral, _amountSCoin, msg.sender, msg.sender);
    }

    /// @notice Redeems collateral without burning any sCoin
    /// @param _collateralToken The address of the collateral token to redeem
    /// @param _amountCollateral The amount of collateral to redeem
    function redeem(address _collateralToken, uint256 _amountCollateral)
        external
        checkCollateralTokenSupported(_collateralToken)
    {
        _redeemAndBurn(_collateralToken, _amountCollateral, 0, msg.sender, msg.sender);
    }

    /// @notice Burns sCoin tokens from the caller
    /// @param _amountSCoin The amount of sCoin to burn
    function burn(uint256 _amountSCoin) external moreThanZero(_amountSCoin) {
        i_sCoin.burn(msg.sender, _amountSCoin);
        s_sCoinBalances[msg.sender] -= _amountSCoin;
        _checkHealthFactor(msg.sender);
    }

    /// @notice Liquidates an undercollateralized position
    /// @param _collateralToken The collateral token to liquidate
    /// @param _user The address of the user to liquidate
    /// @param _debtAmount The amount of debt to repay
    /// @dev Liquidator receives a bonus of collateral tokens for performing the liquidation
    function liquidate(address _collateralToken, address _user, uint256 _debtAmount)
        external
        moreThanZero(_debtAmount)
    {
        uint256 initialHealthFactor = _getHealthFactor(_user);
        if (initialHealthFactor >= HEALTH_FACTOR_THRESHOLD) {
            revert HUB__HealthFactorEnough();
        }

        uint256 tokenAmount = getCollateralTokenAmount(_collateralToken, _debtAmount);
        uint256 tokenAmountPlusBonus = _addBonus(tokenAmount);
        uint256 depositedCollateralAmount = s_collateralBalances[_user][_collateralToken];

        // If health factor is between 100-110%, maximize the liquidation amount
        if (tokenAmount < depositedCollateralAmount && tokenAmountPlusBonus > depositedCollateralAmount) {
            tokenAmountPlusBonus = depositedCollateralAmount;
        }

        if (tokenAmountPlusBonus > depositedCollateralAmount) {
            revert HUB__NotEnoughCollateral();
        }
        _redeemAndBurn(_collateralToken, tokenAmountPlusBonus, _debtAmount, _user, msg.sender);

        // health factor should be improved
        uint256 endingHealthFactor = _getHealthFactor(_user);
        if (endingHealthFactor <= initialHealthFactor) {
            revert HUB__HealthFactorTooLow();
        }
    }

    /// @notice Gets the current health factor for a user
    /// @param user The address of the user to check
    /// @return The health factor scaled by PRECISION (1e18)
    function getHealthFactor(address user) external view returns (uint256) {
        return _getHealthFactor(user);
    }

    /// @notice Returns the minimum required health factor
    /// @return The minimum health factor threshold scaled by PRECISION (1e18)
    function getMinHealthFactor() external pure returns (uint256) {
        return HEALTH_FACTOR_THRESHOLD;
    }

    /// @notice Gets the total USD value of all collateral for a user
    /// @param _user The address of the user to check
    /// @return The total collateral value in USD (scaled by PRECISION)
    function getCollateralValueInUSDForUser(address _user) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < s_supportedCollateralTokens.length; i++) {
            address collateralToken = s_supportedCollateralTokens[i];
            uint256 collateralAmount = s_collateralBalances[_user][collateralToken];
            uint256 price = _getPriceFromChainlink(collateralToken);
            // set precision to 18
            totalCollateralValue += collateralAmount * price / PRECISION;
        }
        return totalCollateralValue;
    }

    /// @notice Gets the amount of a specific collateral token deposited by a user
    /// @param _user The address of the user to check
    /// @param _collateralToken The address of the collateral token
    /// @return The amount of collateral tokens deposited
    function getCollateralAmountForUser(address _user, address _collateralToken) public view returns (uint256) {
        return s_collateralBalances[_user][_collateralToken];
    }

    /// @notice Gets the USD value of a specified amount of collateral tokens
    /// @param _collateralToken The address of the collateral token
    /// @param _tokenAmount The amount of tokens to check
    /// @return The USD value scaled by PRECISION
    function getTokenValueInUSD(address _collateralToken, uint256 _tokenAmount) public view returns (uint256) {
        uint256 tokenPrice = _getPriceFromChainlink(_collateralToken);
        return _tokenAmount * tokenPrice / PRECISION;
    }

    /// @notice Calculates the amount of collateral tokens needed to cover a debt amount
    /// @param _collateralToken The address of the collateral token
    /// @param _debtAmount The amount of debt to cover
    /// @return The amount of collateral tokens needed
    function getCollateralTokenAmount(address _collateralToken, uint256 _debtAmount) public view returns (uint256) {
        uint256 tokenPrice = _getPriceFromChainlink(_collateralToken);
        return _debtAmount * PRECISION / tokenPrice;
    }

    function _addBonus(uint256 _value) private pure returns (uint256) {
        return _value + _value * BONUS / BONUS_PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal function to redeem collateral and burn sCoin
    /// @param _collateralToken The address of the collateral token to redeem
    /// @param _amountCollateral The amount of collateral to redeem
    /// @param _amountSCoin The amount of sCoin to burn
    /// @param from The address to redeem from
    /// @param to The address to send collateral to
    function _redeemAndBurn(
        address _collateralToken,
        uint256 _amountCollateral,
        uint256 _amountSCoin,
        address from,
        address to
    ) private checkCollateralTokenSupported(_collateralToken) {
        if (_amountCollateral > s_collateralBalances[from][_collateralToken]) {
            revert HUB__NotEnoughCollateral();
        }
        s_collateralBalances[from][_collateralToken] -= _amountCollateral;
        bool success = IERC20(_collateralToken).transfer(to, _amountCollateral);
        if (!success) {
            revert HUB__TransferFailed();
        }
        emit CollateralRedeem(address(this), to, _collateralToken, _amountCollateral);

        s_sCoinBalances[from] -= _amountSCoin;
        i_sCoin.burn(to, _amountSCoin);

        _checkHealthFactor(from);
    }

    /// @notice Checks if a user's health factor is above the minimum threshold
    /// @param user The address of the user to check
    /// @dev Reverts if health factor is below HEALTH_FACTOR_THRESHOLD
    function _checkHealthFactor(address user) private view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < HEALTH_FACTOR_THRESHOLD) {
            revert HUB__HealthFactorTooLow();
        }
    }

    /// @notice Calculates the health factor for a given user
    /// @param _user The address of the user
    /// @return The health factor scaled by PRECISION (1e18)
    function _getHealthFactor(address _user) private view returns (uint256) {
        uint256 collaterVal = getCollateralValueInUSDForUser(_user);
        uint256 sCoinVal = s_sCoinBalances[_user];
        if (sCoinVal == 0) {
            return type(uint256).max;
        }
        return collaterVal * PRECISION * LIQUIDATION_THRESHOLD / (sCoinVal * LIQUIDATION_PRECISION);
    }

    /// @notice Gets the latest price from Chainlink price feed
    /// @param _collateralToken The token address to get price for
    /// @return The price normalized to 18 decimals
    function _getPriceFromChainlink(address _collateralToken) private view returns (uint256) {
        // Call Chainlink price feed
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[_collateralToken]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        return uint256(price) * (10 ** uint256(18 - decimals));
    }
}
