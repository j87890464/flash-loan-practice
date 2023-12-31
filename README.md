# 借貸協議與閃電貸（Flash Loan）

## 借貸協議: Compound V2
    * cERC20 的 decimals 皆為 18
    * 部署 cERC20 的 underlying ERC20 token，decimals 為 18
    * 使用 `SimplePriceOracle` 作為 Oracle
    * 使用 `WhitePaperInterestRateModel` 作為利率模型，利率模型合約中的借貸利率設定為 0%
    * 初始 exchangeRate 為 1:1

## Usage

### Build

```shell
$ forge build
```

### Setting
Set RPC_SEPOLIA_URL, PRIVATE_KEY environment variables in .env file.

### Test

Test deploy compound V2
```shell
$ forge test --mc DeployCompoundV2Test
```
