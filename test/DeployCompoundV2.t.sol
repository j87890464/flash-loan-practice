// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import { DeployCompoundV2Script } from "../script/DeployCompoundV2.s.sol";
import { CompoundV2DeploymentStorage } from "../script/CompoundV2DeploymentStorage.sol";
import { EIP20Interface } from "compound-protocol/contracts/EIP20Interface.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";

contract DeployCompoundV2Test is Test, CompoundV2DeploymentStorage {
    uint constant MANTISSA = 1e18;
    DeployCompoundV2Script public deployCompoundV2;
    address public compoundAdmin;
    address public userA;

    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

    function setUp() public {
        deployCompoundV2 = new DeployCompoundV2Script();
        compoundV2Deployment = deployCompoundV2.run();
        compoundAdmin = compoundV2Deployment.admin;
        userA = makeAddr("userA");
    }

    function testDeployment() public {
        assertTrue(compoundV2Deployment.priceOracle != address(0), "deploy PriceOracle failed.");
        assertEq(address(Comptroller(compoundV2Deployment.unitroller).oracle()), compoundV2Deployment.priceOracle, "Comtroller's priceOracle is incorrect.");
        assertTrue(compoundV2Deployment.unitroller != address(0), "deploy Unitroller failed.");
        assertEq(Unitroller(payable(compoundV2Deployment.unitroller)).admin(), compoundV2Deployment.admin, "Unitroller's admin is incorrect.");
        assertTrue(compoundV2Deployment.comptroller != address(0), "deploy Comptroller failed.");
        assertTrue(compoundV2Deployment.interestRateModel != address(0), "deploy InterestRateModel failed.");
        assertTrue(compoundV2Deployment.cErc20Delegate != address(0), "deploy CErc20Delegate failed.");
        assertEq(EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).decimals(), 18, "tokenA decimals is incorrect.");
        assertEq(EIP20Interface(deployCompoundV2.cTokens("cTA")).decimals(), 18, "cTokenA decimals is incorrect.");
        assertEq(EIP20Interface(deployCompoundV2.underlyingTokens("cTB")).decimals(), 18, "tokenB decimals is incorrect.");
        assertEq(EIP20Interface(deployCompoundV2.cTokens("cTB")).decimals(), 18, "cTokenB decimals is incorrect.");
        assertEq(CErc20(deployCompoundV2.cTokens("cTA")).borrowRatePerBlock(), 0, "cTokenA initial borrowRate is incorrect.");
        assertEq(CErc20(deployCompoundV2.cTokens("cTB")).borrowRatePerBlock(), 0, "cTokenB initial borrowRate is incorrect.");
    }

    function testPriceOracle() public {
        CErc20 tokenA =  CErc20(deployCompoundV2.cTokens("cTA"));
        SimplePriceOracle priceOracle = SimplePriceOracle(compoundV2Deployment.priceOracle);
        assertEq(priceOracle.getUnderlyingPrice(tokenA), 0, "token A's initial underlyingPrice is incorrect.");
        uint oldPrice = 0;
        uint newPrice = 100 * MANTISSA;
        vm.expectEmit();
        emit PricePosted(deployCompoundV2.underlyingTokens("cTA"), oldPrice, newPrice, newPrice);
        priceOracle.setUnderlyingPrice(tokenA, newPrice);
        assertEq(priceOracle.getUnderlyingPrice(tokenA), newPrice, "setUnderlyingPrice failed.");
        vm.expectEmit();
        oldPrice = 100 * MANTISSA;
        newPrice = 0;
        emit PricePosted(deployCompoundV2.underlyingTokens("cTA"), oldPrice, newPrice, newPrice);
        priceOracle.setDirectPrice(deployCompoundV2.underlyingTokens("cTA"), newPrice);
        assertEq(priceOracle.getUnderlyingPrice(tokenA), newPrice, "setDirectPrice failed.");
    }

    function testMintCTokenA() public {
        vm.startPrank(userA);
        uint mintAmount = 1000_000 * 10 ** CErc20(deployCompoundV2.underlyingTokens("cTA")).decimals();
        deal(deployCompoundV2.underlyingTokens("cTA"), userA, mintAmount);
        EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).approve(deployCompoundV2.cTokens("cTA"), mintAmount);
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).mint(mintAmount);
        assertEq(CErc20(deployCompoundV2.cTokens("cTA")).balanceOf(userA), mintAmount, "mintAmount incorrect.");
        vm.stopPrank();
    }

    function testMintAndRedeemCTokenA() public {
        testMintCTokenA();
        vm.startPrank(userA);
        uint redeemAmount = 1000_000 * 10 ** EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).decimals();
        CErc20Delegator(payable(deployCompoundV2.cTokens("cTA"))).redeem(redeemAmount);
        assertEq(EIP20Interface(deployCompoundV2.underlyingTokens("cTA")).balanceOf(userA), redeemAmount, "redeemAmount incorrect.");
        vm.stopPrank();
    }
}


