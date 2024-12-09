// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {Deploy} from "../../script/Deploy.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {SCoin} from "../../src/SCoin.sol";
import {Hub} from "../../src/Hub.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";

/// @title Hub Contract Unit Tests
/// @notice Contains unit tests for the Hub contract's core functionality
contract HubTest is Test {
    Deploy deployer;
    Hub hub;
    SCoin scoin;
    HelperConfig config;
    address weth;
    address wbtc;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant COLLATERAL_AMOUNT = 1e18;
    uint256 public constant MINT_AMOUNT = 100e18;

    /// @notice Sets up the test environment before each test
    /// @dev Deploys contracts, mints tokens, and sets up approvals
    function setUp() public {
        deployer = new Deploy();
        (scoin, hub, config) = deployer.run();
        (weth, wbtc, wethUsdPriceFeed, wbtcUsdPriceFeed) = config.networkConfig();

        // Fund user with WETH and WBTC
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
        scoin.mint(LIQUIDATOR, 1000e18);

        vm.startPrank(USER);
        IERC20(weth).approve(address(hub), type(uint256).max);
        IERC20(wbtc).approve(address(hub), type(uint256).max);
        scoin.approve(address(hub), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        IERC20(weth).approve(address(hub), type(uint256).max);
        IERC20(wbtc).approve(address(hub), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests the calculation of collateral token amounts from sCoin amounts
    function testGetCollateralTokenAmountFromSCoinAmount() public view {
        uint256 debtAmount = 100e18;
        uint256 expectedWethAmount = 0.025e18; // 100 / 4000 = 0.025

        uint256 actualWethAmount = hub.getCollateralTokenAmount(weth, debtAmount);
        assertEq(actualWethAmount, expectedWethAmount);

        uint256 expectedWbtcAmount = 0.001_111_111_111_111_111 ether; // 100 / 90000 ≈ 0.00111...
        uint256 actualWbtcAmount = hub.getCollateralTokenAmount(wbtc, debtAmount);
        assertEq(actualWbtcAmount, expectedWbtcAmount);
    }

    /// @notice Tests the calculation of token values in USD
    function testGetTokenValueInUSD() public view {
        uint256 collateralAmount = 1e18;
        uint256 expectedWethValueInUSD = 4000e18; // 1 ETH = $4000

        uint256 actualWethValueInUSD = hub.getTokenValueInUSD(weth, collateralAmount);
        assertEq(actualWethValueInUSD, expectedWethValueInUSD);

        uint256 expectedWbtcValueInUSD = 90000e18; // 1 BTC = $90000
        uint256 actualWbtcValueInUSD = hub.getTokenValueInUSD(wbtc, collateralAmount);
        assertEq(actualWbtcValueInUSD, expectedWbtcValueInUSD);
    }

    /// @notice Tests the health factor calculation
    function test_GetHealthFactor() public {
        vm.startPrank(USER);
        uint256 collateralAmount = 1 ether;
        uint256 mintAmount = 2000 ether; // $2000 worth of sCoin

        hub.depositAndMint(weth, collateralAmount, mintAmount);

        // 1 ETH = $4000
        // Liquidation threshold = 50%
        // Collateral value = $4000 * 0.5 = $2000
        // Health factor = ($2000 * 1e18) / $2000 = 1e18
        uint256 expectedHealthFactor = hub.getMinHealthFactor();
        uint256 actualHealthFactor = hub.getHealthFactor(USER);

        assertEq(actualHealthFactor, expectedHealthFactor);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests that constructor reverts if token and price feed arrays don't match
    function testRevertsIfLengthNotMatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = wbtc;

        address[] memory feeds = new address[](1);
        feeds[0] = wethUsdPriceFeed;

        vm.expectRevert(Hub.HUB__LengthNotMatch.selector);
        new Hub(address(scoin), tokens, feeds);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT AND MINT TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Tests successful deposit of collateral and minting of sCoin
    function testCanDepositCollateralAndMintSCoin() public {
        vm.startPrank(USER);

        hub.depositAndMint(weth, COLLATERAL_AMOUNT, MINT_AMOUNT);

        uint256 healthFactor = hub.getHealthFactor(USER);
        assertGt(healthFactor, hub.getMinHealthFactor());
        assertEq(IERC20(weth).balanceOf(address(hub)), COLLATERAL_AMOUNT);
        assertEq(scoin.balanceOf(USER), MINT_AMOUNT);

        vm.stopPrank();
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(Hub.HUB__AmountMustBeMoreThanZero.selector);
        hub.depositAndMint(weth, 0, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testRevertsIfHealthFactorTooLow() public {
        vm.startPrank(USER);
        uint256 tooHighMintUSD = 1_000_000e18;
        vm.expectRevert(Hub.HUB__HealthFactorTooLow.selector);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, tooHighMintUSD);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        // Create a mock token that always returns false for transferFrom
        MockFailedTransferFrom mockToken = new MockFailedTransferFrom();
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockToken);
        address[] memory priceFeeds = new address[](1);
        priceFeeds[0] = wethUsdPriceFeed;

        Hub newHub = new Hub(address(scoin), tokens, priceFeeds);

        vm.startPrank(USER);
        mockToken.mint(USER, COLLATERAL_AMOUNT);
        vm.expectRevert(Hub.HUB__TransferFailed.selector);
        newHub.depositAndMint(address(mockToken), COLLATERAL_AMOUNT, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testRevertsWithUnsupportedCollateral() public {
        // Create a random ERC20 token that is not supported by the hub
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(USER, COLLATERAL_AMOUNT);

        vm.startPrank(USER);
        randomToken.approve(address(hub), COLLATERAL_AMOUNT);
        vm.expectRevert(Hub.HUB__CollateralTokenNotSupported.selector);
        hub.depositAndMint(address(randomToken), COLLATERAL_AMOUNT, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testCanDepositWithoutMinting() public {
        vm.startPrank(USER);

        uint256 initialBalance = IERC20(weth).balanceOf(USER);
        hub.deposit(weth, COLLATERAL_AMOUNT);

        assertEq(IERC20(weth).balanceOf(USER), initialBalance - COLLATERAL_AMOUNT);
        assertEq(IERC20(weth).balanceOf(address(hub)), COLLATERAL_AMOUNT);
        assertEq(scoin.balanceOf(USER), 0);

        vm.stopPrank();
    }

    function testGetCollateralValueInUSDForUser() public {
        vm.startPrank(USER);
        hub.deposit(weth, COLLATERAL_AMOUNT);

        uint256 expectedValueInUSD = hub.getTokenValueInUSD(weth, COLLATERAL_AMOUNT);
        uint256 actualValueInUSD = hub.getCollateralValueInUSDForUser(USER);

        assertEq(actualValueInUSD, expectedValueInUSD);
        assertEq(scoin.balanceOf(USER), 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertsIfMintAmountExceedsCollateralValue() public {
        vm.startPrank(USER);
        IERC20(weth).approve(address(hub), COLLATERAL_AMOUNT);

        uint256 tooMuchMintAmount = 1_000_000e18;

        vm.expectRevert(Hub.HUB__HealthFactorTooLow.selector);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, tooMuchMintAmount);
        vm.stopPrank();
    }

    function testCanMintMoreWithoutBreakingHealthFactor() public {
        vm.startPrank(USER);
        // With ETH at $4000, depositing COLLATERAL_AMOUNT (10e18 ETH = $40,000)
        // Minting 1000 sCoin is well within the health factor since it's only $1000
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 1000e18);

        uint256 initialHealthFactor = hub.getHealthFactor(USER);

        // Can mint 500 more sCoin ($500) since we're still well collateralized
        uint256 additionalMint = 500e18;
        hub.mint(additionalMint);

        uint256 finalHealthFactor = hub.getHealthFactor(USER);

        // Health factor should be lower but still above threshold
        // (We've only minted $1500 worth against $40,000 collateral)
        assertGt(initialHealthFactor, finalHealthFactor);
        assertGt(finalHealthFactor, hub.getMinHealthFactor());

        // Check balances
        assertEq(scoin.balanceOf(USER), 1500e18); // 1000 + 500
        vm.stopPrank();
    }

    function testCannotMintMoreIfBreakingHealthFactor() public {
        vm.startPrank(USER);
        // First deposit and mint a reasonable amount
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 1000e18);

        // Try to mint an amount that would break health factor
        uint256 tooMuchAdditionalMint = 1050e18;

        vm.expectRevert(Hub.HUB__HealthFactorTooLow.selector);
        hub.mint(tooMuchAdditionalMint);

        // Original balance should remain unchanged
        assertEq(scoin.balanceOf(USER), 1000e18);
        vm.stopPrank();
    }

    function testCannotMintZero() public {
        vm.startPrank(USER);
        // First deposit some collateral
        hub.deposit(weth, COLLATERAL_AMOUNT);

        // Try to mint 0 sCoin
        vm.expectRevert(Hub.HUB__AmountMustBeMoreThanZero.selector);
        hub.mint(0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanBurnSCoin() public {
        vm.startPrank(USER);
        // First deposit and mint
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 1000e18);

        uint256 initialHealthFactor = hub.getHealthFactor(USER);

        // Burn half the sCoin
        uint256 burnAmount = 500e18;
        hub.burn(burnAmount);

        uint256 finalHealthFactor = hub.getHealthFactor(USER);

        // Health factor should improve after burning
        assertGt(finalHealthFactor, initialHealthFactor);

        // Check balance
        assertEq(scoin.balanceOf(USER), 500e18); // 1000 - 500
        vm.stopPrank();
    }

    function testCannotBurnMoreThanBalance() public {
        vm.startPrank(USER);
        // First deposit and mint
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 1000e18);

        // Try to burn more than we have
        uint256 tooMuchBurn = 1500e18;

        vm.expectRevert();
        hub.burn(tooMuchBurn);

        // Balance should remain unchanged
        assertEq(scoin.balanceOf(USER), 1000e18);
        vm.stopPrank();
    }

    function testCannotBurnZero() public {
        vm.startPrank(USER);
        // First deposit and mint
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 1000e18);

        // Try to burn 0 sCoin
        vm.expectRevert(Hub.HUB__AmountMustBeMoreThanZero.selector);
        hub.burn(0);

        // Balance should remain unchanged
        assertEq(scoin.balanceOf(USER), 1000e18);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanRedeemCollateral() public {
        vm.startPrank(USER);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, MINT_AMOUNT);

        uint256 initialBalance = IERC20(weth).balanceOf(USER);
        hub.redeemAndBurn(weth, COLLATERAL_AMOUNT, MINT_AMOUNT);

        assertEq(IERC20(weth).balanceOf(USER), initialBalance + COLLATERAL_AMOUNT);
        assertEq(scoin.balanceOf(USER), 0);
        vm.stopPrank();
    }

    function testCannotRedeemMoreThanCollateral() public {
        vm.startPrank(USER);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, MINT_AMOUNT);

        vm.expectRevert(Hub.HUB__NotEnoughCollateral.selector);
        hub.redeemAndBurn(weth, COLLATERAL_AMOUNT + 1, MINT_AMOUNT);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCanLiquidateUserWithLowHealthFactor() public {
        // First, let's get a user into a position where they can be liquidated
        vm.startPrank(USER);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 2000e18);
        vm.stopPrank();

        uint256 initialHealthFactor = hub.getHealthFactor(USER);
        console.log("Initial Health Factor: ", initialHealthFactor);

        // Now crash the price of ETH
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(3900e8);

        vm.startPrank(LIQUIDATOR);
        // Should be able to liquidate now
        uint256 debtToCover = 200e18;
        hub.liquidate(weth, USER, debtToCover);
        vm.stopPrank();

        uint256 endingHealthFactor = hub.getHealthFactor(USER);
        console.log("Ending Health Factor: ", endingHealthFactor);
    }

    function testCantLiquidateWithGoodHealthFactor() public {
        vm.startPrank(USER);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, MINT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(Hub.HUB__HealthFactorEnough.selector);
        hub.liquidate(weth, USER, MINT_AMOUNT);
        vm.stopPrank();
    }

    function testLiquidatorGetsCorrectBonus() public {
        // Setup: User deposits collateral and mints SCoin
        vm.startPrank(USER);
        hub.depositAndMint(weth, COLLATERAL_AMOUNT, 2000e18);
        vm.stopPrank();

        // Crash ETH price to make user liquidatable
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(3900e8);

        uint256 debtToCover = 200e18;
        uint256 expectedCollateralAmount = hub.getCollateralTokenAmount(weth, debtToCover);
        // Bonus is 10% (BONUS/BONUS_PRECISION = 10/100)
        uint256 expectedBonus = expectedCollateralAmount / 10;
        uint256 totalExpectedPayout = expectedCollateralAmount + expectedBonus;

        uint256 liquidatorInitialBalance = IERC20(weth).balanceOf(LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        hub.liquidate(weth, USER, debtToCover);
        vm.stopPrank();

        uint256 liquidatorFinalBalance = IERC20(weth).balanceOf(LIQUIDATOR);
        uint256 actualPayout = liquidatorFinalBalance - liquidatorInitialBalance;

        assertEq(actualPayout, totalExpectedPayout, "Liquidator didn't receive correct bonus amount");
        assertEq(
            IERC20(weth).balanceOf(USER) + actualPayout + IERC20(weth).balanceOf(address(hub)),
            STARTING_USER_BALANCE,
            "Total ETH should equal original deposit"
        );
    }

    function testCriticalHealthFactor() public {
        // Setup liquidator
        uint256 liquidatorCollateral = 10e18;
        ERC20Mock(weth).mint(LIQUIDATOR, liquidatorCollateral);
        vm.startPrank(LIQUIDATOR);
        hub.depositAndMint(weth, liquidatorCollateral, MINT_AMOUNT);
        vm.stopPrank();

        // Set initial prices
        int256 wethUsdPrice = 105e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(wethUsdPrice);
        int256 wbtcUsdPrice = 95e8;
        MockV3Aggregator(wbtcUsdPriceFeed).updateAnswer(wbtcUsdPrice);

        // User deposits both WETH and WBTC and mints SCoin
        uint256 amountWethToDeposit = 1e18;
        uint256 amountWbtcToDeposit = 1e18;
        uint256 amountSCoinToMint = 100e18;
        vm.startPrank(USER);
        hub.deposit(weth, amountWethToDeposit);
        hub.depositAndMint(wbtc, amountWbtcToDeposit, amountSCoinToMint);
        vm.stopPrank();

        // WBTC price crashes to 0
        MockV3Aggregator(wbtcUsdPriceFeed).updateAnswer(0);

        // Liquidator tries to liquidate full amount - shouldn't revert
        vm.startPrank(LIQUIDATOR);
        hub.liquidate(weth, USER, amountSCoinToMint);
        vm.stopPrank();
    }
}
