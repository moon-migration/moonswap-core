# moonswap-amm
## Migrator

- MigratorFactory

createpair and get Custodian RecevieAddress(cToken Type), from ethereum transfer then crosschain club mint cToken, transfer ERC777 to MigratorPair

- MigratorPair

receive crosschain fund; Add LIQUIDITY
user exchange LpToken through cMoonLpToken;
upload User ShareAmount Then airdrop FC;

## MoonSwap

- MoonSwap Factory (=UniswapV2Factory)

same as Uniswap;

limit createPair;
limit tokenlist;

- MoonSwap Pair (= UniswapV2Pair)

same as Uniswap;


## Contract Address

- `mainnet`
base on conflux

| Name | Contract Address (hex) |
| --- | --- |
| MoonswapRouter | 0x80ae6a88ce3351e9f729e8199f2871ba786ad7c5 |
| MoonswapFactory | 0x865f55a399bf9250ae781adfbed71e70c12bd2d8 |
| inithash | a6330451e4d6d3fc19f31fc5ee71147d88812b0da79f64b03ed210fd594d84e9|
| MoonCake | 0x86897fff70592e3973f637b39da4208797192a1a |
| MoonMaker | 0x854b73aa9f5b713c2244560c13107f19422f1e49 |

- `testnet`

| Name | Contract Address (hex) |
| --- | --- |
| MoonswapRouter | 0x8a38553900e5d1f83a76c83b09522929691112d0 |
| MoonswapFactory | 0x8c1bf1bce2e9c0a5822fd106b0aac39bf02be779 |
