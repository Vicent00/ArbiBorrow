# Lending/Borrowing Protocol

Un protocolo de préstamos y colateralización basado en WETH y USDC, utilizando Uniswap v3 TWAP como oráculo de precios.

## Características

- Depósito de WETH como colateral
- Préstamos de USDC con LTV máximo del 75%
- Sistema de liquidaciones con bonus del 5%
- Oráculo TWAP de Uniswap v3
- Interés fijo del 3% APR

## Arquitectura

### Contratos Principales

- `UniswapTwapOracle.sol`: Oráculo de precios basado en TWAP de Uniswap v3
- `LendingPool.sol`: Contrato principal de lending/borrowing

### Flujo de Usuario

1. **Depósito**
   - Usuario aprueba WETH
   - Usuario deposita WETH como colateral

2. **Préstamo**
   - Usuario solicita préstamo en USDC
   - Sistema verifica LTV máximo (75%)

3. **Repago**
   - Usuario repaga USDC más intereses
   - Sistema actualiza la posición

4. **Retiro**
   - Usuario retira WETH manteniendo LTV seguro
   - Sistema verifica health factor

5. **Liquidación**
   - Liquidador repaga deuda
   - Recibe colateral + 5% bonus

## Desarrollo

### Requisitos

- Foundry
- Solidity 0.8.26
- Node.js

### Instalación

```bash
# Clonar repositorio
git clone https://github.com/your-username/lending-protocol.git
cd lending-protocol

# Instalar dependencias
forge install

# Compilar contratos
forge build

# Ejecutar pruebas
forge test
```

### Pruebas

```bash
# Ejecutar todas las pruebas
forge test

# Ejecutar pruebas con cobertura
forge coverage

# Ejecutar pruebas de fuzzing
forge test --match-test "testFuzz"
```

## Seguridad

- Auditoría interna
- Pruebas exhaustivas
- Validaciones de precio
- Sistema de heartbeat para el oráculo
- Límites de cambio de precio

## Despliegue

El protocolo está diseñado para ser desplegado en Arbitrum Mainnet.

### Direcciones de Contratos

- WETH: `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1`
- USDC: `0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8`
- Uniswap V3 Pool: `0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443`

## Licencia

MIT
