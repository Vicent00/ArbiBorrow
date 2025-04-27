// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "../lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../lib/v3-core/contracts/libraries/TickMath.sol";
import "../lib/v3-core/contracts/libraries/FullMath.sol";

/**
 * @title UniswapTwapOracle
 * @notice Oracle that provides TWAP prices from Uniswap V3 pool with additional safety checks
 */
contract UniswapTwapOracle is Ownable, ReentrancyGuard {
    using SafeCast for uint256;
    using SafeCast for int256;

    IUniswapV3Pool public immutable pool;
    uint32 public immutable twapWindow;
    
    uint256 public constant MIN_PRICE = 1e6;   // Precio mínimo aceptable
    uint256 public constant MAX_PRICE = 1e32;  // Precio máximo aceptable
    uint128 public minLiquidity;               // Liquidez mínima requerida
    
    // Nuevas variables para mejoras
    uint256 public lastUpdateTimestamp;        // Última actualización del precio
    uint256 public constant HEARTBEAT = 1 hours; // Tiempo máximo entre actualizaciones
    uint256 public lastValidPrice;             // Último precio válido
    uint256 public constant MAX_PRICE_CHANGE = 50; // Máximo cambio de precio permitido (50%)
    uint256 public constant PRICE_PRECISION = 1e18; // Precisión para cálculos de precio

    error InvalidTwapWindow();
    error InvalidPool();
    error PriceTooLow();
    error PriceTooHigh();
    error InsufficientLiquidity();
    error StalePrice();
    error PriceChangeTooLarge();
    error OracleNotInitialized();

    event PriceUpdated(uint256 price, uint256 timestamp);
    event MinLiquidityUpdated(uint128 newMinLiquidity);
    event HeartbeatMissed(uint256 lastUpdate, uint256 currentTime);

    /**
     * @notice Constructor
     * @param _pool Address of the Uniswap V3 pool
     * @param _twapWindow TWAP window in seconds
     * @param _minLiquidity Minimum liquidity required in the pool
     */
    constructor(
        address _pool, 
        uint32 _twapWindow,
        uint128 _minLiquidity
    ) Ownable(msg.sender) {
        if (_pool == address(0)) revert InvalidPool();
        if (_twapWindow == 0) revert InvalidTwapWindow();
        
        pool = IUniswapV3Pool(_pool);
        twapWindow = _twapWindow;
        minLiquidity = _minLiquidity;
        lastUpdateTimestamp = block.timestamp;
    }

    /**
     * @notice Get the TWAP price from the pool with additional safety checks
     * @return price The TWAP price with 18 decimals
     */
    function getTwapPrice() external view returns (uint256 price) {
        // Verificar liquidez mínima
        uint128 currentLiquidity = pool.liquidity();
        if (currentLiquidity < minLiquidity) revert InsufficientLiquidity();

        // Verificar heartbeat
        if (block.timestamp - lastUpdateTimestamp > HEARTBEAT) {
            revert StalePrice();
        }

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
        
        // Calculate the arithmetic mean tick
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int56 timeDelta = int56(uint56(twapWindow));
        int24 arithmeticMeanTick = int24(tickCumulativesDelta / timeDelta);

        // Convert tick to price using TickMath
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        uint256 price = FullMath.mulDiv(
            uint256(sqrtPriceX96),
            uint256(sqrtPriceX96),
            1 << 192
        );

        // Validaciones de precio
        if (price < MIN_PRICE) revert PriceTooLow();
        if (price > MAX_PRICE) revert PriceTooHigh();

        // Verificar cambio de precio máximo
        if (lastValidPrice > 0) {
            uint256 priceChange = price > lastValidPrice ? 
                ((price - lastValidPrice) * 100) / lastValidPrice :
                ((lastValidPrice - price) * 100) / lastValidPrice;
            
            if (priceChange > MAX_PRICE_CHANGE) revert PriceChangeTooLarge();
        }

        return price;
    }

    /**
     * @notice Get the latest price from the pool with safety checks
     * @return price The latest price with 18 decimals
     */
    function getLatestPrice() external view returns (uint256 price) {
        // Verificar liquidez mínima
        uint128 currentLiquidity = pool.liquidity();
        if (currentLiquidity < minLiquidity) revert InsufficientLiquidity();
        
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        
        uint256 price = FullMath.mulDiv(
            uint256(sqrtPriceX96),
            uint256(sqrtPriceX96),
            1 << 192
        );

        // Validaciones de precio
        if (price < MIN_PRICE) revert PriceTooLow();
        if (price > MAX_PRICE) revert PriceTooHigh();

        // Verificar cambio de precio máximo
        if (lastValidPrice > 0) {
            uint256 priceChange = price > lastValidPrice ? 
                ((price - lastValidPrice) * 100) / lastValidPrice :
                ((lastValidPrice - price) * 100) / lastValidPrice;
            
            if (priceChange > MAX_PRICE_CHANGE) revert PriceChangeTooLarge();
        }

        return price;
    }

    /**
     * @notice Update the minimum liquidity requirement
     * @param _minLiquidity New minimum liquidity value
     */
    function setMinLiquidity(uint128 _minLiquidity) external onlyOwner {
        minLiquidity = _minLiquidity;
        emit MinLiquidityUpdated(_minLiquidity);
    }

    /**
     * @notice Update the last valid price and timestamp
     * @param _price New price value
     */
    function updatePrice(uint256 _price) external {
        if (_price < MIN_PRICE) revert PriceTooLow();
        if (_price > MAX_PRICE) revert PriceTooHigh();

        lastValidPrice = _price;
        lastUpdateTimestamp = block.timestamp;
        emit PriceUpdated(_price, block.timestamp);
    }

    /**
     * @notice Check if the oracle is healthy
     * @return bool True if the oracle is healthy
     */
    function isHealthy() external view returns (bool) {
        return block.timestamp - lastUpdateTimestamp <= HEARTBEAT;
    }
}