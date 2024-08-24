// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

contract UpsideAcademyLending {
    IPriceOracle public priceOracle;
    address public reserveToken;

    constructor(IPriceOracle upsideOracle, address token) {
        priceOracle = upsideOracle;
        reserveToken = token;
    }

    function initializeLendingProtocol(address token) external payable {
        
    }

    function deposit(address token, uint256 amount) external payable{
        require(msg.value > 0, "Deposit value error");
    }

    function withdraw(address token, uint256 amount) external {
        
    }

    function borrow(address token, uint256 amount) external {
        
    }

    function repay(address token, uint256 amount) external {
        
    }

    function liquidate(address borrower, address token, uint256 amount) external {
        
    }

    function getAccruedSupplyAmount(address token) external returns (uint256) {
        
    }
}

contract UpsideOracle {
    mapping(address => uint256) prices;

    function getPrice(address token) external returns (uint256) {
        
    }

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }
}