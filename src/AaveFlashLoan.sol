// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool } from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import { CTokenInterface, CErc20Interface } from "compound-protocol/contracts/CTokenInterfaces.sol";
import { ISwapRouter } from "v3-periphery/interfaces/ISwapRouter.sol";

contract AaveFlashLoan is IFlashLoanSimpleReceiver {
  address public immutable usdc;
  address public immutable uni;
  address public immutable poolAddressProvider;
  address public immutable uniswapRouter;

  constructor(address _usdc, address _uni, address _poolAddressProvider, address _uniswapRouter) {
    usdc = _usdc;
    uni = _uni;
    poolAddressProvider = _poolAddressProvider;
    uniswapRouter = _uniswapRouter;
  }

  struct LiquidationParams {
    address loanToken;
    uint loanAmount;
    address target;
    address borrower;
    uint repayAmount;
    address collateral;
  }

  function executeOperation(
    address asset,
    uint256 amount,
    uint256 premium,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    // Compound V2 liquidate
    // cUNI -> UNI (redeem)
    // UNI -> USDC (uniswap)
    // Aave payback USDC (approve)
    LiquidationParams memory liquidationParams = abi.decode(params, (LiquidationParams));
    IERC20(liquidationParams.loanToken).approve(liquidationParams.target, liquidationParams.repayAmount);
    CErc20Interface(payable(liquidationParams.target)).liquidateBorrow(liquidationParams.borrower, liquidationParams.repayAmount, CTokenInterface(liquidationParams.collateral));
    CErc20Interface(payable(liquidationParams.collateral)).redeem(IERC20(liquidationParams.collateral).balanceOf(address(this)));
    IERC20(uni).approve(uniswapRouter, IERC20(uni).balanceOf(address(this)));
    ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
        tokenIn: uni,
        tokenOut: usdc,
        fee: 3000, // 0.3%
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: IERC20(uni).balanceOf(address(this)),
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    });
    uint256 amountOut = ISwapRouter(uniswapRouter).exactInputSingle(swapParams);
    uint paybackAmount = liquidationParams.loanAmount + premium;
    IERC20(asset).approve(msg.sender, paybackAmount);

    return true;
  }

  function execute(bytes memory params) external {
    LiquidationParams memory liquidationParams = abi.decode(params, (LiquidationParams));
    POOL().flashLoanSimple(
    address(this),
    usdc,
    liquidationParams.loanAmount,
    params,
    0
  );
  }

  function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
    return IPoolAddressesProvider(poolAddressProvider);
  }

  function POOL() public view returns (IPool) {
    return IPool(ADDRESSES_PROVIDER().getPool());
  }
}
