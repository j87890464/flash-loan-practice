// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract CompoundV2DeploymentStorage {
    struct CompoundV2Deployment {
        address payable admin;
        address priceOracle;
        address unitroller;
        address comptroller;
        address interestRateModel;
        address cErc20Delegate;
    }

    CompoundV2Deployment public compoundV2Deployment;
}
