// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "./UniswapTwapOracle.sol";

/**
 * @title LendingPool
 * @notice Core contract for the lending/borrowing protocol
 */
contract LendingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // Tokens
    IERC20 public immutable weth;
    IERC20 public immutable usdc;
    
    // Oracle
    UniswapTwapOracle public immutable oracle;
    
    // Constants
    uint256 public constant LTV_MAX = 75; // 75% LTV máximo
    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80% threshold para liquidación
    uint256 public constant LIQUIDATION_BONUS = 5; // 5% bonus para liquidadores
    uint256 public constant INTEREST_RATE = 3; // 3% APR
    uint256 public constant PRECISION = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    
    // Límites por usuario
    uint256 public constant MAX_COLLATERAL_PER_USER = 1000 * 10**18; // 1000 WETH máximo por usuario
    uint256 public constant MAX_DEBT_PER_USER = 400000 * 10**18; // 400k USDC máximo por usuario
    
    // Lista de liquidables
    address[] public liquidationCandidates;
    mapping(address => bool) public isInLiquidationList;
    
    // Structs
    struct Position {
        uint128 collateral;    // Colateral en WETH
        uint128 debt;          // Deuda en USDC
        uint40 lastAccrued;    // Timestamp del último accrue
        uint128 accruedInterest; // Interés acumulado
    }
    
    // State
    mapping(address => Position) public positions;
    uint256 public totalCollateral;
    uint256 public totalDebt;
    uint256 public lastUpdateTimestamp;
    
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed user, address indexed liquidator, uint256 collateralAmount, uint256 debtAmount);
    event AccrueInterest(address indexed user, uint256 interestAmount);
    event PositionUpdated(address indexed user, uint256 collateral, uint256 debt);
    event LiquidationStatusUpdated(address indexed user, bool isLiquidable);
    event LiquidationListCleaned(uint256 removedCount);
    
    // Errors
    error InsufficientCollateral();
    error ExcessiveBorrow();
    error InsufficientLiquidity();
    error PositionNotLiquidatable();
    error OracleError();
    error InvalidAmount();
    error UnhealthyOracle();
    error InvalidLTV();
    error InvalidHealthFactor();
    error MaxCollateralExceeded();
    error MaxDebtExceeded();
    error UserNotInLiquidationList();
    
    /**
     * @notice Constructor
     * @param _weth Address of WETH token
     * @param _usdc Address of USDC token
     * @param _oracle Address of the TWAP oracle
     */
    constructor(
        address _weth,
        address _usdc,
        address _oracle
    ) Ownable(msg.sender) {
        weth = IERC20(_weth);
        usdc = IERC20(_usdc);
        oracle = UniswapTwapOracle(_oracle);
        lastUpdateTimestamp = block.timestamp;
    }
    
    /**
     * @notice Update liquidation status for a user
     * @param user Address of the user to update
     */
    function updateLiquidationStatus(address user) public {
        uint256 healthFactor = getHealthFactor(user);
        bool isLiquidable = healthFactor < PRECISION;
        
        if (isLiquidable && !isInLiquidationList[user]) {
            liquidationCandidates.push(user);
            isInLiquidationList[user] = true;
            emit LiquidationStatusUpdated(user, true);
        } else if (!isLiquidable && isInLiquidationList[user]) {
            // Remove from list
            for (uint256 i = 0; i < liquidationCandidates.length; i++) {
                if (liquidationCandidates[i] == user) {
                    liquidationCandidates[i] = liquidationCandidates[liquidationCandidates.length - 1];
                    liquidationCandidates.pop();
                    break;
                }
            }
            isInLiquidationList[user] = false;
            emit LiquidationStatusUpdated(user, false);
        }
    }
    
    /**
     * @notice Clean liquidation list
     * @param max Maximum number of users to check
     */
    function cleanLiquidationList(uint256 max) external onlyOwner {
        uint256 removed = 0;
        uint256 i = 0;
        
        while (i < liquidationCandidates.length && removed < max) {
            address user = liquidationCandidates[i];
            uint256 healthFactor = getHealthFactor(user);
            
            if (healthFactor >= PRECISION) {
                // Remove from list
                liquidationCandidates[i] = liquidationCandidates[liquidationCandidates.length - 1];
                liquidationCandidates.pop();
                isInLiquidationList[user] = false;
                removed++;
            } else {
                i++;
            }
        }
        
        emit LiquidationListCleaned(removed);
    }
    
    /**
     * @notice Get all liquidation candidates
     * @return Array of addresses that are liquidable
     */
    function getLiquidationCandidates() external view returns (address[] memory) {
        return liquidationCandidates;
    }
    
    /**
     * @notice Deposit WETH as collateral
     * @param amount Amount of WETH to deposit
     */
    function deposit(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        Position storage position = positions[msg.sender];
        
        // Check max collateral limit
        if (position.collateral + amount > MAX_COLLATERAL_PER_USER) revert MaxCollateralExceeded();
        
        // Update position
        position.collateral += uint128(amount);
        position.lastAccrued = uint40(block.timestamp);
        
        totalCollateral += amount;

        
        
        // Transfer WETH from user
        weth.safeTransferFrom(msg.sender, address(this), amount);
        
         // Update liquidation status
        updateLiquidationStatus(msg.sender);
       
        
        emit Deposit(msg.sender, amount);
        emit PositionUpdated(msg.sender, position.collateral, position.debt);
    }
    
    /**
     * @notice Withdraw WETH collateral
     * @param amount Amount of WETH to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        Position storage position = positions[msg.sender];
        
        // Accrue interest
        _accrueInterest(msg.sender);
        
        // Check LTV
        uint256 price = _getPrice();
        uint256 collateralValue = (position.collateral * price) / PRECISION;
        uint256 maxWithdraw = (collateralValue * (100 - LTV_MAX)) / 100;
        
        if (amount > maxWithdraw) revert ExcessiveBorrow();
        
        // Update position
        position.collateral -= uint128(amount);
        totalCollateral -= amount;

        
        // Transfer WETH to user
        weth.safeTransfer(msg.sender, amount);

         // Update liquidation status
        updateLiquidationStatus(msg.sender);
        
        emit Withdraw(msg.sender, amount);
        emit PositionUpdated(msg.sender, position.collateral, position.debt);
    }
    
    /**
     * @notice Borrow USDC
     * @param amount Amount of USDC to borrow
     */
    function borrow(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        Position storage position = positions[msg.sender];
        
        // Accrue interest
        _accrueInterest(msg.sender);
        
        // Check max debt limit
        if (position.debt + amount > MAX_DEBT_PER_USER) revert MaxDebtExceeded();
        
        // Check LTV
        uint256 price = _getPrice();
        uint256 collateralValue = (position.collateral * price) / PRECISION;
        uint256 maxBorrow = (collateralValue * LTV_MAX) / 100;
        
        if (amount > maxBorrow) revert ExcessiveBorrow();
        
        // Check protocol liquidity
        if (amount > usdc.balanceOf(address(this))) revert InsufficientLiquidity();
        
        // Update position
        position.debt += uint128(amount);
        totalDebt += amount;
        
        // Transfer USDC to user
        usdc.safeTransfer(msg.sender, amount);
        
        // Update liquidation status
        updateLiquidationStatus(msg.sender);
        
        emit Borrow(msg.sender, amount);
        emit PositionUpdated(msg.sender, position.collateral, position.debt);
    }
    
    /**
     * @notice Repay USDC debt
     * @param amount Amount of USDC to repay
     */
    function repay(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidAmount();
        
        Position storage position = positions[msg.sender];
        
        // Accrue interest
        _accrueInterest(msg.sender);
        
        // Update position
        position.debt -= uint128(amount);
        totalDebt -= amount;
        
        // Transfer USDC from user
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update liquidation status
        updateLiquidationStatus(msg.sender);
        
        emit Repay(msg.sender, amount);
        emit PositionUpdated(msg.sender, position.collateral, position.debt);
    }
    
    /**
     * @notice Liquidate an unhealthy position
     * @param user Address of the user to liquidate
     * @param maxUsdcAmount Maximum amount of USDC to repay
     */
    function liquidate(address user, uint256 maxUsdcAmount) external nonReentrant {
        if (!isInLiquidationList[user]) revert UserNotInLiquidationList();
        
        Position storage position = positions[user];
        
        // Accrue interest
        _accrueInterest(user);
        
        // Check if position is liquidatable
        uint256 healthFactor = getHealthFactor(user);
        if (healthFactor >= PRECISION) revert PositionNotLiquidatable();
        
        // Calculate liquidation amounts
        uint256 debtToRepay = Math.min(maxUsdcAmount, position.debt);
        uint256 collateralToSeize = (debtToRepay * (100 + LIQUIDATION_BONUS)) / 100;
        
        // Update position
        position.debt -= uint128(debtToRepay);
        position.collateral -= uint128(collateralToSeize);
        
        totalDebt -= debtToRepay;
        totalCollateral -= collateralToSeize;
        
        // Transfer tokens
        usdc.safeTransferFrom(msg.sender, address(this), debtToRepay);
        weth.safeTransfer(msg.sender, collateralToSeize);
        
        emit Liquidate(user, msg.sender, collateralToSeize, debtToRepay);
        emit PositionUpdated(user, position.collateral, position.debt);
    }
    
    /**
     * @notice Accrue interest for a position
     * @param user Address of the user
     */
    function _accrueInterest(address user) internal {
        Position storage position = positions[user];
        
        if (position.debt == 0) return;
        
        uint256 timeElapsed = block.timestamp - position.lastAccrued;
        uint256 interest = (position.debt * INTEREST_RATE * timeElapsed) / (SECONDS_PER_YEAR * 100);
        
        position.debt += uint128(interest);
        position.accruedInterest += uint128(interest);
        position.lastAccrued = uint40(block.timestamp);
        
        totalDebt += interest;
        
        emit AccrueInterest(user, interest);
    }
    
    /**
     * @notice Get the current price from the oracle
     * @return price The current price
     */
    function _getPrice() internal view returns (uint256) {
        if (!oracle.isHealthy()) revert UnhealthyOracle();
        return oracle.getTwapPrice();
    }
    
    /**
     * @notice Get the health factor of a position
     * @param user Address of the user
     * @return healthFactor The health factor
     */
    function getHealthFactor(address user) public view returns (uint256) {
        Position storage position = positions[user];
        if (position.debt == 0) return type(uint256).max;
        
        uint256 price = _getPrice();
        uint256 collateralValue = (position.collateral * price) / PRECISION;
        return (collateralValue * PRECISION) / (position.debt * LIQUIDATION_THRESHOLD);
    }
    
    /**
     * @notice Get the maximum borrow amount for a user
     * @param user Address of the user
     * @return maxBorrow The maximum borrow amount
     */
    function getMaxBorrow(address user) external view returns (uint256) {
        Position storage position = positions[user];
        uint256 price = _getPrice();
        uint256 collateralValue = (position.collateral * price) / PRECISION;
        return (collateralValue * LTV_MAX) / 100;
    }
    
    /**
     * @notice Get the maximum withdraw amount for a user
     * @param user Address of the user
     * @return maxWithdraw The maximum withdraw amount
     */
    function getMaxWithdraw(address user) external view returns (uint256) {
        Position storage position = positions[user];
        uint256 price = _getPrice();
        uint256 collateralValue = (position.collateral * price) / PRECISION;
        return (collateralValue * (100 - LTV_MAX)) / 100;
    }
    
    /**
     * @notice Get the total value locked in the protocol
     * @return tvl The total value locked
     */
    function getTVL() external view returns (uint256) {
        uint256 price = _getPrice();
        return (totalCollateral * price) / PRECISION;
    }
} 