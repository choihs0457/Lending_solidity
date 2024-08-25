// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/forge-std/src/console.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

contract UpsideAcademyLending {
    IPriceOracle public priceOracle;
    address public reserveToken;

    mapping(address => uint256) public userBorrow;
    mapping(address => uint256) public userBorrowInterest;
    mapping(address => uint256) public tokenDeposits;
    mapping(address => uint256) public userDepositInterest;
    mapping(address => mapping(address => uint256)) public tokenUserDeposits;
    mapping(address => uint256) public lastBorrowBlock;

    constructor(IPriceOracle upsideOracle, address token) {
        priceOracle = upsideOracle;
        reserveToken = token;
    }

    modifier accrueInterest() {
        if (userBorrow[msg.sender] > 0) {
            uint256 blocksPassed = block.number - lastBorrowBlock[msg.sender];
            uint256 borrowInterest = (userBorrow[msg.sender] * 66 * blocksPassed) / 100000;
            userBorrowInterest[msg.sender] += borrowInterest;
        }
        if (tokenUserDeposits[msg.sender][reserveToken] > 0) {
            uint256 blocksPassed = block.number - lastBorrowBlock[msg.sender];
            uint256 depositInterest = (tokenUserDeposits[msg.sender][reserveToken] * 13889255555555 * blocksPassed) / 1 ether;
            userDepositInterest[msg.sender] += depositInterest;
        }
        lastBorrowBlock[msg.sender] = block.number;
        _;
    }

    function initializeLendingProtocol(address token) external payable {
        require(token == reserveToken && msg.value > 0, "check tokens and value");
        ERC20(token).transferFrom(msg.sender, address(this), msg.value);
        tokenUserDeposits[msg.sender][token] += msg.value;
        tokenDeposits[token] += msg.value;
    }

    function deposit(address token, uint256 amount) external payable {
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

    function withdraw(address token, uint256 amount) external accrueInterest {
        require(tokenDeposits[token] >= amount, "check amount");
        (uint256 ethPrice, uint256 usdcPrice) = tokenPrice();
        uint256 collateralValue = tokenUserDeposits[msg.sender][token] * ethPrice / 1 ether;
        uint256 totalDebt = userBorrow[msg.sender] + userBorrowInterest[msg.sender];

        if (totalDebt > 0) {
            uint256 newCollateralValue = collateralValue - (amount * ethPrice / 1 ether);
            require(newCollateralValue > 0, "check amount");
            uint256 lt = (totalDebt * 100) / newCollateralValue;
            require(lt <= 75, "75% over");
            require(totalDebt <= 75 * newCollateralValue, "check amount");
        }
        tokenUserDeposits[msg.sender][token] -= amount;
        tokenDeposits[token] -= amount;

        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            ERC20(token).transfer(msg.sender, amount);
        }
    }

    function borrow(address token, uint256 amount) external accrueInterest {
        require(tokenDeposits[token] >= amount, "check amount");
        (uint256 ethPrice, uint256 usdcPrice) = tokenPrice();
        uint256 collateralValue = tokenUserDeposits[msg.sender][address(0x0)] * ethPrice / 1 ether;
        uint256 totalDebt = userBorrow[msg.sender] + userBorrowInterest[msg.sender] + amount;

        uint256 lt = totalDebt / collateralValue;
        uint256 borrowable = collateralValue * 50008 / 100000;

        require(100000 * lt <= 50008, "50.008% over");
        require(totalDebt <= borrowable, "check amount");

        userBorrow[msg.sender] += amount;
        tokenDeposits[token] -= amount;

        ERC20(token).transfer(msg.sender, amount);
    }

    function repay(address token, uint256 amount) external accrueInterest {
        uint256 totalDebt = userBorrow[msg.sender] + userBorrowInterest[msg.sender];
        require(totalDebt >= amount, "check amount");

        if (amount > userBorrowInterest[msg.sender]) {
            uint256 remaining = amount - userBorrowInterest[msg.sender];
            userBorrowInterest[msg.sender] = 0;
            userBorrow[msg.sender] -= remaining;
        } else {
            userBorrowInterest[msg.sender] -= amount;
        }

        tokenDeposits[token] += amount;

        ERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function liquidate(address borrower, address token, uint256 amount) external {
        (uint256 ethPrice, uint256 usdcPrice) = tokenPrice();
        uint256 totalDebt = userBorrow[borrower] + userBorrowInterest[borrower];
        require(totalDebt > 0, "check debt");

        uint256 collateralValue = tokenUserDeposits[borrower][address(0x0)] * ethPrice / 1 ether;
        uint256 lt = (totalDebt * 1000) / collateralValue;
        require(lt > 750, "Loan is still healthy");

        uint amount = amount * usdcPrice / 1 ether;

        uint256 maxLiquidationAmount;
        if (totalDebt <= 100 ether) {
            maxLiquidationAmount = totalDebt; 
        } else {
            maxLiquidationAmount = totalDebt / 4;
        }

        require(amount <= maxLiquidationAmount, "check amount");
        if (amount > userBorrowInterest[borrower]) {
            uint256 remaining = amount - userBorrowInterest[borrower];
            userBorrowInterest[borrower] = 0;
            userBorrow[borrower] -= remaining;
        } else {
            userBorrowInterest[borrower] -= amount;
        }

        tokenDeposits[token] += amount;

        ERC20(token).transferFrom(msg.sender, address(this), amount);

        uint256 collateralToLiquidate = (amount * 1 ether) / ethPrice;
        tokenUserDeposits[borrower][address(0x0)] -= collateralToLiquidate;

        payable(msg.sender).transfer(collateralToLiquidate);

        collateralValue = tokenUserDeposits[borrower][address(0x0)] * ethPrice / 1 ether;
        lt = (userBorrow[borrower] + userBorrowInterest[borrower]) * 1000 / collateralValue;
        require(lt < 750 || userBorrow[borrower] == 0, "check amount");
    }

    function getAccruedSupplyAmount(address token) external accrueInterest returns (uint256) {
        uint256 insterest = userDepositInterest[msg.sender];
        userDepositInterest[msg.sender] = 0;

        return insterest;
    }

    function tokenPrice() internal returns (uint256, uint256) {
        uint256 ethPrice = priceOracle.getPrice(address(0x0));
        uint256 usdcPrice = priceOracle.getPrice(reserveToken);
        return (ethPrice, usdcPrice);
    }
    // function calcCollateralValue(address owner, address token) internal returns (uint256) {
    //     uint256 collateralValue = tokenUserDeposits[owner][token] * usdcPrice / 1 ether;
    //     return collateralValue;
    // }

}