// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool } from "aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";
import { CTokenInterface, CErc20Interface } from "compound-protocol/contracts/CTokenInterfaces.sol";
import { ISwapRouter } from "v3-periphery/interfaces/ISwapRouter.sol";

contract AaveFlashLoan is IFlashLoanSimpleReceiver {
  address public immutable admin;
  address public immutable usdc;
  address public immutable uni;
  address public immutable poolAddressProvider;
  address public immutable uniswapRouter;

  modifier onlyAdmin() {
    require(msg.sender == admin, "only admin is allowed.");
    _;
  }

  constructor(address _usdc, address _uni, address _poolAddressProvider, address _uniswapRouter) {
    admin = msg.sender;
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
    // Compound V2: liquidateBorrow
    //  - cUNI -> UNI (redeem)
    // Uniswap: UNI -> USDC (exactInputSingle)
    // Aave: payback USDC (approve)
    require(msg.sender == address(POOL()), "sender must from Aave.");
    require(initiator == address(this), "initiator must be this contract.");

    LiquidationParams memory liquidationParams = abi.decode(params, (LiquidationParams));
    IERC20(asset).approve(liquidationParams.target, liquidationParams.repayAmount);
    (uint _success) = CErc20Interface(payable(liquidationParams.target)).liquidateBorrow(liquidationParams.borrower, liquidationParams.repayAmount, CTokenInterface(liquidationParams.collateral));
    require(_success == 0, "liquidateBorrow failed.");
    (_success) = CErc20Interface(payable(liquidationParams.collateral)).redeem(IERC20(liquidationParams.collateral).balanceOf(address(this)));
    require(_success == 0, "redeem failed.");
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
    uint paybackAmount = amount + premium;
    require(amountOut >= paybackAmount, "Insufficient amountOut.");
    IERC20(asset).approve(msg.sender, paybackAmount);

    return true;
  }

  function execute(bytes memory params) external {
    LiquidationParams memory liquidationParams = abi.decode(params, (LiquidationParams));
    POOL().flashLoanSimple(
      address(this),
      liquidationParams.loanToken,
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

  function withdraw(address token) public onlyAdmin {
    IERC20(token).transfer(admin, IERC20(token).balanceOf(address(this)));
  }

  function withdrawEth() public onlyAdmin {
    payable(admin).call{value: address(this).balance}("");
  }
}
