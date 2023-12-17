// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { DeployCompoundV2Script } from "../script/DeployCompoundV2.s.sol";
import { CompoundV2DeploymentStorage } from "../script/CompoundV2DeploymentStorage.sol";
import { EIP20Interface } from "compound-protocol/contracts/EIP20Interface.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { AaveFlashLoan } from "../src/AaveFlashLoan.sol";
import { ISwapRouter } from "v3-periphery/interfaces/ISwapRouter.sol";

contract DeployCompoundV2Test is Test, CompoundV2DeploymentStorage {
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    string SEPOLIA_RPC_URL = vm.envString("SEPOLIA_RPC_URL");
    uint public constant MANTISSA = 18;
    uint public constant protocolSeizeShareMantissa = 2.8e16;
    uint public liquidationIncentive;
    uint public closeFactor;
    DeployCompoundV2Script public deployCompoundV2;
    address public userA;
    address public userB;
    address public userC;
    address public constant UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // 18
    address public constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // 6
    address public constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; 

    AaveFlashLoan aaveFlashLoan;

    struct LiquidationParams {
        address loanToken;
        uint loanAmount;
        address target;
        address borrower;
        uint repayAmount;
        address collateral;
    }

    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);
    event Mint(address minter, uint mintAmount, uint mintTokens);
    event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);
    event Borrow(address borrower, uint borrowAmount, uint accountBorrows, uint totalBorrows);
    event RepayBorrow(address payer, address borrower, uint repayAmount, uint accountBorrows, uint totalBorrows);
    event LiquidateBorrow(address liquidator, address borrower, uint repayAmount, address cTokenCollateral, uint seizeTokens);

    modifier mainnetFork {
        uint256 fork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(fork);
        vm.roll(17465000);
        _;
    }

    modifier sepoliaFork {
        uint256 fork = vm.createFork(SEPOLIA_RPC_URL);
        vm.selectFork(fork);
        _;
    }

    function setUp() mainnetFork public {
        _deployCompoundV2OnMainnet();
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        vm.label(deployCompoundV2.underlyingTokens("cTA"), "tokenA");
        vm.label(deployCompoundV2.underlyingTokens("cTB"), "tokenB");
        vm.label(deployCompoundV2.cTokens("cTA"), "cTokenA");
        vm.label(deployCompoundV2.cTokens("cTB"), "cTokenB");
        vm.label(compoundV2Deployment.admin, "Compound admin");
        closeFactor = 1 * 10 ** MANTISSA;
        _setCloseFactor(closeFactor);
        liquidationIncentive = 108 * 10 ** MANTISSA / 100;
        _setLiquidationIncentive(liquidationIncentive);
    }

    function testDeployment() public {
        assertTrue(compoundV2Deployment.priceOracle != address(0), "deploy PriceOracle failed.");
        assertEq(address(Comptroller(compoundV2Deployment.unitroller).oracle()), compoundV2Deployment.priceOracle, "Comtroller's priceOracle is incorrect.");
        assertTrue(compoundV2Deployment.unitroller != address(0), "deploy Unitroller failed.");
        assertEq(Unitroller(payable(compoundV2Deployment.unitroller)).admin(), compoundV2Deployment.admin, "Unitroller's admin is incorrect.");
        assertTrue(compoundV2Deployment.comptroller != address(0), "deploy Comptroller failed.");
        assertTrue(compoundV2Deployment.interestRateModel != address(0), "deploy InterestRateModel failed.");
        assertTrue(compoundV2Deployment.cErc20Delegate != address(0), "deploy CErc20Delegate failed.");
        assertEq(EIP20Interface(deployCompoundV2.cTokens("cTA")).decimals(), 18, "cTokenA decimals is incorrect.");
        assertEq(EIP20Interface(deployCompoundV2.cTokens("cTB")).decimals(), 18, "cTokenB decimals is incorrect.");
        assertEq(CErc20(deployCompoundV2.cTokens("cTA")).borrowRatePerBlock(), 0, "cTokenA initial borrowRate is incorrect.");
        assertEq(CErc20(deployCompoundV2.cTokens("cTB")).borrowRatePerBlock(), 0, "cTokenB initial borrowRate is incorrect.");
    }

    function testPriceOracle() public {
        CErc20 tokenA =  CErc20(deployCompoundV2.cTokens("cTA"));
        SimplePriceOracle priceOracle = SimplePriceOracle(compoundV2Deployment.priceOracle);
        assertEq(priceOracle.getUnderlyingPrice(tokenA), 0, "token A's initial underlyingPrice is incorrect.");
        uint _oldPrice = 0;
        uint _newPrice = 100 * 10 ** MANTISSA;
        vm.expectEmit();
        emit PricePosted(deployCompoundV2.underlyingTokens("cTA"), _oldPrice, _newPrice, _newPrice);
        _setPrice(deployCompoundV2.underlyingTokens("cTA"), _newPrice);
        assertEq(priceOracle.getUnderlyingPrice(tokenA), _newPrice, "setUnderlyingPrice failed.");
        vm.expectEmit();
        _oldPrice = 100 * 10 ** MANTISSA;
        _newPrice = 0;
        emit PricePosted(deployCompoundV2.underlyingTokens("cTA"), _oldPrice, _newPrice, _newPrice);
        _setPrice(deployCompoundV2.underlyingTokens("cTA"), _newPrice);
        assertEq(priceOracle.getUnderlyingPrice(tokenA), _newPrice, "setDirectPrice failed.");
    }

    function testMintCTokenA() public {
        vm.startPrank(userA);
        uint _mintAmount = 100 * 10 ** CErc20(deployCompoundV2.underlyingTokens("cTA")).decimals();
        deal(deployCompoundV2.underlyingTokens("cTA"), userA, _mintAmount);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), _mintAmount);
        vm.expectEmit();
        uint _mintTokens = 100 * 10 ** MANTISSA;
        emit Mint(userA, _mintAmount, _mintTokens);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).mint(_mintAmount);
        assertEq(CErc20(deployCompoundV2.cTokens("cTA")).balanceOf(userA), _mintTokens, "mintTokens is incorrect.");
        vm.stopPrank();
    }

    // Mint and redeem case:
    //   1.userA mint 100e18 cTokenA
    //   2.userA redeem 100e18 tokenA
    function testMintAndRedeemCTokenA() public {
        testMintCTokenA();
        vm.startPrank(userA);
        uint _redeemATokens = 100 * 10 ** MANTISSA;
        uint _redeemAmount = 100 * 10 ** EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).decimals();
        vm.expectEmit();
        emit Redeem(userA, _redeemAmount, _redeemATokens);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).redeem(_redeemATokens);
        assertEq(EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).balanceOf(userA), _redeemAmount, "redeemAmount is incorrect.");     
        vm.stopPrank();
    }

    function testBorrow() public {
        _setPrice(deployCompoundV2.underlyingTokens("cTA"), 1 * 10 ** MANTISSA);
        _setPrice(deployCompoundV2.underlyingTokens("cTB"), 100 * 10 ** MANTISSA);
        CToken _cTB = CToken(deployCompoundV2.cTokens("cTB"));
        _setCollateralFactor(_cTB, 50 * 10 ** (MANTISSA - 2));
        uint _mintAmount = 1 * 10 ** MANTISSA;
        uint _borrowAmount = 50 * 10 ** MANTISSA;
        deal(deployCompoundV2.underlyingTokens("cTB"), userA, _mintAmount);
        deal(deployCompoundV2.underlyingTokens("cTA"), userB, _borrowAmount);
        vm.startPrank(userB);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), _borrowAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).mint(_borrowAmount);
        vm.stopPrank();

        vm.startPrank(userA);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTB")).approve(deployCompoundV2.cTokens("cTB"), _mintAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTB"))).mint(_mintAmount);
        address[] memory cTokens = new address[](1);
        cTokens[0] = deployCompoundV2.cTokens("cTB");
        Comptroller(compoundV2Deployment.unitroller).enterMarkets(cTokens);
        uint _beforeBalance = EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).balanceOf(userA);
        vm.expectEmit();
        emit Borrow(userA, _borrowAmount, _borrowAmount, _borrowAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).borrow(_borrowAmount);
        uint _afterBalance = EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).balanceOf(userA);
        assertEq(_afterBalance - _beforeBalance, _borrowAmount, "borrow amount is incorrect.");
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), _borrowAmount);
        vm.stopPrank();
    }

    // Borrow and repay case:
    // tokenA price: 1$, tokenB price: 100$
    // tokenB collateral factor: 50%
    // closeFactor: 100%
    //   1.userA mint 1 cTokenB
    //   2.use cTokenB as collactor to borrow 50 tokenA
    //   3.repay 50 tokenA
    function testBorrowAndRepay() public {
        testBorrow();
        vm.startPrank(userA);
        uint _repayAmount = 50 * 10 ** MANTISSA;
        vm.expectEmit();
        emit RepayBorrow(userA, userA, _repayAmount, 0, 0);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).repayBorrow(_repayAmount);
        vm.stopPrank();
    }

    // Liquidation case1:
    //   1.based on borrow case
    //   2.Compound admin alter collateralFactor of tokenB to 40%(less than previous one: 50%)
    //   3.userB can liquidate userA's borrow now.
    function testLiquidation_ViaAlterCollateralFactor() public {
        testBorrow();
        CToken _cTB = CToken(deployCompoundV2.cTokens("cTB"));
        _setCollateralFactor(_cTB, 40 * 10 ** MANTISSA / 100);

        vm.startPrank(userB);
        uint _repayAmount = 50 * 10 ** MANTISSA;
        deal(deployCompoundV2.underlyingTokens("cTA"), userB, _repayAmount);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), _repayAmount);
        uint _beforeBalance = EIP20Interface(deployCompoundV2.cTokens("cTB")).balanceOf(userB);
        // userB seizeTokens = (actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral) / exchangeRate * (1 - protocolSeizeShareMantissa)
        uint _seizeAmount = _divWithMantissa(_mulWithMantissa(_mulWithMantissa(_repayAmount, liquidationIncentive) ,1 * 10 ** MANTISSA), 100 * 10 ** MANTISSA);
        uint _seizeTokens = _mulWithMantissa(_divWithMantissa(_seizeAmount ,1 * 10 ** MANTISSA), (1 * 10 ** MANTISSA - protocolSeizeShareMantissa));
        vm.expectEmit();
        emit LiquidateBorrow(userB, userA, _repayAmount, deployCompoundV2.cTokens("cTB"), _seizeAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).liquidateBorrow(userA, _repayAmount, CToken(deployCompoundV2.cTokens("cTB")));
        uint _afterBalance = EIP20Interface(deployCompoundV2.cTokens("cTB")).balanceOf(userB);
        assertEq(_afterBalance - _beforeBalance, _seizeTokens, "seize tokens is incorrect.");
        vm.stopPrank();
    }

    // Liquidation case2:
    //   1.based on borrow case
    //   2.alter price of tokenB to 90$(less than previous: 100$)
    //   3.userB can liquidate userA's borrow now.
    function testLiquidation_ViaAlterTokenBPrice() public {
        testBorrow();
        CToken _cTB = CToken(deployCompoundV2.cTokens("cTB"));
        uint _newPrice = 90 * 10 ** MANTISSA;
        _setPrice(deployCompoundV2.underlyingTokens("cTB"), _newPrice);

        vm.startPrank(userB);
        uint _repayAmount = 50 * 10 ** MANTISSA;
        deal(deployCompoundV2.underlyingTokens("cTA"), userB, _repayAmount);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), _repayAmount);
        uint _beforeBalance = EIP20Interface(deployCompoundV2.cTokens("cTB")).balanceOf(userB);
        // userB seizeTokens = (actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral) / exchangeRate * (1 - protocolSeizeShareMantissa)
        uint _seizeAmount = _divWithMantissa(_mulWithMantissa(_mulWithMantissa(_repayAmount, liquidationIncentive) ,1 * 10 ** MANTISSA), _newPrice);
        uint _seizeTokens = _mulWithMantissa(_divWithMantissa(_seizeAmount ,1 * 10 ** MANTISSA), (1 * 10 ** MANTISSA - protocolSeizeShareMantissa));
        vm.expectEmit();
        emit LiquidateBorrow(userB, userA, _repayAmount, deployCompoundV2.cTokens("cTB"), _seizeAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).liquidateBorrow(userA, _repayAmount, CToken(deployCompoundV2.cTokens("cTB")));
        uint _afterBalance = EIP20Interface(deployCompoundV2.cTokens("cTB")).balanceOf(userB);
        assertEq(_afterBalance - _beforeBalance, _seizeTokens, "seize tokens is incorrect.");
        vm.stopPrank();
    }

    // Liquidation case3:
    function testLiquidation_ViaAaveV3() public {
        // block: 17465000
        assertEq(block.number, 17_465_000, "incorrect block number.");
        
        _setCloseFactor(50 * 10 ** MANTISSA / 100);
        _setPrice(deployCompoundV2.underlyingTokens("cTA"), 1 * 10 ** (36 - CErc20(deployCompoundV2.underlyingTokens("cTA")).decimals()));
        _setPrice(deployCompoundV2.underlyingTokens("cTB"), 5 * 10 ** (36 - CErc20(deployCompoundV2.underlyingTokens("cTB")).decimals()));
        CToken _cTB = CToken(deployCompoundV2.cTokens("cTB"));
        _setCollateralFactor(_cTB, 50 * 10 ** MANTISSA / 100);

        vm.startPrank(userC);
        uint _borrowAmount = 2500 * 10 ** CErc20(deployCompoundV2.underlyingTokens("cTA")).decimals();
        deal(deployCompoundV2.underlyingTokens("cTA"), userC, _borrowAmount);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), _borrowAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).mint(_borrowAmount);
        vm.stopPrank();

        vm.startPrank(userA);
        uint _mintAmount = 1000 * 10 ** CErc20(deployCompoundV2.underlyingTokens("cTB")).decimals();
        deal(deployCompoundV2.underlyingTokens("cTB"), userA, _mintAmount);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTB")).approve(deployCompoundV2.cTokens("cTB"), _mintAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTB"))).mint(_mintAmount);
        address[] memory cTokens = new address[](1);
        cTokens[0] = deployCompoundV2.cTokens("cTB");
        Comptroller(compoundV2Deployment.unitroller).enterMarkets(cTokens);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).borrow(_borrowAmount);
        vm.stopPrank();
        
        // UNI price: From 5$ to 4$
        _setPrice(deployCompoundV2.underlyingTokens("cTB"), 4 * 10 ** (36 - CErc20(deployCompoundV2.underlyingTokens("cTB")).decimals()));

        vm.startPrank(userA);
        aaveFlashLoan = new AaveFlashLoan(USDC_ADDRESS, UNI_ADDRESS, POOL_ADDRESSES_PROVIDER, UNISWAP_ROUTER);
        LiquidationParams memory liquidationParams;
        liquidationParams.loanToken = USDC_ADDRESS;
        liquidationParams.loanAmount = 1000 * 10 ** CErc20(deployCompoundV2.underlyingTokens("cTA")).decimals();
        liquidationParams.target = deployCompoundV2.cTokens("cTA");
        liquidationParams.borrower = userA;
        liquidationParams.repayAmount = 1000 * 10 ** CErc20(deployCompoundV2.underlyingTokens("cTA")).decimals();
        liquidationParams.collateral = deployCompoundV2.cTokens("cTB");
        
        aaveFlashLoan.execute(abi.encode(liquidationParams));
        vm.stopPrank();
    }

    function _deployCompoundV2OnMainnet() private mainnetFork {
        _deployCompoundV2();
    }

    function _deployCompoundV2OnSepolia() private sepoliaFork {
        _deployCompoundV2();
    }

    function _deployCompoundV2() private mainnetFork {
        deployCompoundV2 = new DeployCompoundV2Script();
        compoundV2Deployment = deployCompoundV2.run();
    }

    function _setPrice(address _underlyingToken, uint _price) private {
        require(compoundV2Deployment.priceOracle != address(0), "priceOracle is not ready.");
        vm.startPrank(compoundV2Deployment.admin);
        SimplePriceOracle(compoundV2Deployment.priceOracle).setDirectPrice(_underlyingToken, _price);
        vm.stopPrank();
    }

    function _setCollateralFactor(CToken _cToken, uint _collateralFactor) private {
        require(compoundV2Deployment.unitroller != address(0), "unitroller is not ready.");
        vm.startPrank(compoundV2Deployment.admin);
        Comptroller(compoundV2Deployment.unitroller)._setCollateralFactor(_cToken, _collateralFactor);
        vm.stopPrank();
    }

    function _setCloseFactor(uint _closeFactor) private {
        require(compoundV2Deployment.unitroller != address(0), "unitroller is not ready.");
        vm.startPrank(compoundV2Deployment.admin);
        Comptroller(compoundV2Deployment.unitroller)._setCloseFactor(_closeFactor);
        vm.stopPrank();
    }

    function _setLiquidationIncentive(uint _liquidationIncentive) private {
        require(compoundV2Deployment.unitroller != address(0), "unitroller is not ready.");
        vm.startPrank(compoundV2Deployment.admin);
        Comptroller(compoundV2Deployment.unitroller)._setLiquidationIncentive(_liquidationIncentive);
        vm.stopPrank();
    }

    function _mulWithMantissa(uint a, uint b) private pure returns(uint) {
        return a * b / (1 * 10 ** MANTISSA);
    }

    function _divWithMantissa(uint a, uint b) private pure returns(uint) {
        return a * (1 * 10 ** MANTISSA) / b;
    }
}