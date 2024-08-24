// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

contract UpsideAcademyLending {
    IPriceOracle public priceOracle;
    address public reserveToken;

    mapping(address => uint256) public tokenDeposits;
    mapping(address => mapping(address => uint256)) public tokenUserDeposits;

    constructor(IPriceOracle upsideOracle, address token) {
        priceOracle = upsideOracle;
        reserveToken = token;
    }

    function initializeLendingProtocol(address token) external payable {
        require(token == reserveToken && msg.value > 0, "check tokens and value");
        ERC20(token).transferFrom(msg.sender, address(this), msg.value);
        tokenUserDeposits[msg.sender][token] += msg.value;
        tokenDeposits[token] += msg.value;
    }

    function deposit(address token, uint256 amount) external payable{
        require(token == reserveToken || msg.value > 0, "Invalid deposit");
        
        if (msg.value > 0) {
            require(token == address(0) && msg.value >= amount, "check tokens and value");
            tokenUserDeposits[msg.sender][token] += msg.value;
            tokenDeposits[token] += msg.value;
        } else {
            require(token == reserveToken && amount > 0, "check tokens and value");
            tokenUserDeposits[msg.sender][token] += amount;
            tokenDeposits[token] += amount;
            ERC20(token).transferFrom(msg.sender, address(this), amount);
        }
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