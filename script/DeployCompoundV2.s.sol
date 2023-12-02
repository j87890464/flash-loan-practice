// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Script, console2 } from "forge-std/Script.sol";
import { CompoundV2DeploymentStorage } from "./CompoundV2DeploymentStorage.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        
    }
}

contract DeployCompoundV2Script is Script, CompoundV2DeploymentStorage {
    uint constant MANTISSA = 1e18;
    uint8 constant DECIMALS = 18;
    Unitroller unitroller;
    Comptroller comptroller;
    mapping(string => address) public cTokens;
    mapping(string => address) public underlyingTokens;

    function setUp() public {
    }

    function run() public returns(CompoundV2Deployment memory) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        compoundV2Deployment.admin = payable(deployer);
        deploySimplePriceOracle();
        deployComptroller();
        deployUnitroller();
        deployWhitePaperInterestRateModel();
        deployCErc20Delegate();
        // ERC20 token A
        deployCTokenA();
        addToSupportMarket(cTokens["cTA"]);
        // ERC20 token B
        deployCTokenB();
        addToSupportMarket(cTokens["cTB"]);
        vm.stopBroadcast();

        return compoundV2Deployment;
    }

    function deploySimplePriceOracle() public returns(address addr) {
        SimplePriceOracle simplePriceOracle = new SimplePriceOracle();
        addr = address(simplePriceOracle);
        compoundV2Deployment.priceOracle = addr;
    }

    function deployUnitroller() public returns(address addr) {
        unitroller = new Unitroller();
        addr = address(unitroller);
        compoundV2Deployment.unitroller = addr;
        setComptrollerImplementation();
        setPriceOracle();
    }

    function deployComptroller() public returns(address addr) {
        comptroller = new Comptroller();
        addr = address(comptroller);
        compoundV2Deployment.comptroller = addr;
    }

    function deployWhitePaperInterestRateModel() public returns(address addr) {
        WhitePaperInterestRateModel whitePaperInterestRateModel = new WhitePaperInterestRateModel(0, 0);
        addr = address(whitePaperInterestRateModel);
        compoundV2Deployment.interestRateModel = addr;
    }

    function deployCErc20Delegate() public returns(address addr) {
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        addr = address(cErc20Delegate);
        compoundV2Deployment.cErc20Delegate = addr;
    }

    function deployCTokenA() public returns(address addr) {
        address tokenA = deployERC20("Token A", "TA");
        underlyingTokens["cTA"] = tokenA;
        CErc20Delegator cTokenA = new CErc20Delegator(
            tokenA,
            Comptroller(compoundV2Deployment.unitroller),
            WhitePaperInterestRateModel(compoundV2Deployment.interestRateModel),
            MANTISSA,
            "Compound tokenA",
            "cTA",
            DECIMALS,
            compoundV2Deployment.admin,
            compoundV2Deployment.cErc20Delegate,
            bytes("")
        );
        cTokens["cTA"] = address(cTokenA);
        addr = address(cTokenA);
    }

    function deployCTokenB() public returns(address addr) {
        address tokenB = deployERC20("Token B", "TB");
        underlyingTokens["cTB"] = tokenB;
        CErc20Delegator cTokenB = new CErc20Delegator(
            tokenB,
            Comptroller(compoundV2Deployment.unitroller),
            WhitePaperInterestRateModel(compoundV2Deployment.interestRateModel),
            MANTISSA,
            "Compound tokenB",
            "cTB",
            DECIMALS,
            compoundV2Deployment.admin,
            compoundV2Deployment.cErc20Delegate,
            bytes("")
        );
        cTokens["cTB"] = address(cTokenB);
        addr = address(cTokenB);
    }

    function deployERC20(string memory _name, string memory _symbol) public returns(address addr) {
        TestERC20 token = new TestERC20(_name, _symbol);
        addr = address(token);
    }

    function setPriceOracle() public {
        Comptroller(compoundV2Deployment.unitroller)._setPriceOracle(SimplePriceOracle(compoundV2Deployment.priceOracle));
    }

    function setComptrollerImplementation() public {
        unitroller._setPendingImplementation(compoundV2Deployment.comptroller);
        comptroller._become(unitroller);
    }

    function addToSupportMarket(address _cToken) public {
        Comptroller(compoundV2Deployment.unitroller)._supportMarket(CErc20Delegate(_cToken));
    }
}
