# Exogenous Collateralized Stablecoin Lending Protocol

A exogenous collateralized stablecoin lending protocol that allows users to deposit collateral and mint synthetic stablecoins (sCoin) against their collateral position.

## Overview

This project implements a collateralized debt position (CDP) system where users can:
- Deposit supported collateral tokens (WETH, WBTC)
- Mint synthetic stablecoins (sCoin) against their collateral
- Maintain a minimum health factor to avoid liquidation
- Redeem their collateral by repaying debt
- Participate in liquidations of unhealthy positions

## Key Features

### Collateral Management
- Multi-collateral support (WETH, WBTC initially)
- Real-time price feeds via Chainlink oracles
- Configurable liquidation thresholds

### Risk Management
- Minimum health factor of 1.0 (100%)
- Liquidation threshold at 50% of collateral value
- Liquidation bonus of 10% to incentivize liquidators

### Core Functions
- `depositAndMint`: Deposit collateral and mint sCoin in one transaction
- `redeemAndBurn`: Repay sCoin and retrieve collateral
- `liquidate`: Liquidate positions below minimum health factor

## Technical Details

### Smart Contracts

- `Hub.sol`: Main contract handling collateral, minting, and liquidations
- `SCoin.sol`: ERC20 implementation of the synthetic stablecoin

### Testing

The system includes comprehensive test coverage:
- Unit tests for all core functions
- Invariant fuzz tests to ensure system-wide properties

### Key Invariants

1. Total sCoin supply must never exceed 50% of total collateral value

### Testing
```bash
forge test
```

