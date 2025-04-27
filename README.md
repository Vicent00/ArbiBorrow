# Lending/Borrowing Protocol

A lending and collateralization protocol based on WETH and USDC, using Uniswap v3 TWAP as a price oracle.

## Features

- WETH deposits as collateral
- USDC loans with maximum 75% LTV
- Liquidation system with 5% bonus
- Uniswap v3 TWAP oracle
- Fixed 3% APR interest rate

## Architecture

### Main Contracts

- `UniswapTwapOracle.sol`: Price oracle based on Uniswap v3 TWAP
- `LendingPool.sol`: Main lending/borrowing contract

### User Flow

1. **Deposit**
   - User approves WETH
   - User deposits WETH as collateral

2. **Borrow**
   - User requests USDC loan
   - System verifies maximum LTV (75%)

3. **Repayment**
   - User repays USDC plus interest
   - System updates position

4. **Withdraw**
   - User withdraws WETH while maintaining safe LTV
   - System verifies health factor

5. **Liquidation**
   - Liquidator repays debt
   - Receives collateral + 5% bonus

## Development

### Requirements

- Foundry
- Solidity 0.8.26
- Node.js

### Installation

```bash
# Clone repository
git clone https://github.com/your-username/lending-protocol.git
cd lending-protocol

# Install dependencies
forge install

# Compile contracts
forge build
```

## Security

- Internal audit
- Comprehensive testing
- Price validations
- Oracle heartbeat system
- Price change limits

## License

MIT
