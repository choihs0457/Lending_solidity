// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/forge-std/src/console.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

contract UpsideAcademyLending {
    IPriceOracle public price_oracle;
    event LogEvent(uint256 message);
    address public usdc;

    struct S_USDC {
        uint256 deposit_amount;
        uint256 borrow_amount;
        uint256 block_number;
    }

    struct S_ETH {
        uint256 deposit_amount;
        uint256 borrow_amount;
        uint256 block_number;
    }


    address[] public lender;
    address[] public borrower;
    
    uint public LT = 75;
    uint public LTV = 50;
    uint public INTEREST_RATE = 1e15;
    uint public INTEREST_RATE_PER_BLOCK = 100000013881950033;
    uint public WAD = 1e18;
    uint public BLOCK_PER_DAY = 7500;
    uint public total_deposit_USDC;
    uint public total_deposit_ETH;
    uint public total_borrow_USDC;
    uint public total_borrow_ETH;

    mapping(address => S_ETH) public user_ETH;
    mapping(address => S_USDC) public user_USDC;
    mapping(address => uint256) public lastBorrowBlock;

    

    mapping(address => uint256) public userBorrow;
    mapping(address => uint256) public userBorrowInterest;
    mapping(address => uint256) public tokenDeposits;
    mapping(address => uint256) public userDepositInterest;
    mapping(address => mapping(address => uint256)) public tokenUserDeposits;

    constructor(IPriceOracle upsideOracle, address token) {
        price_oracle = upsideOracle;
        usdc = token;
    }

    modifier accrueInterest() {
        if(user_USDC[msg.sender].block_number < block.number){
            uint distance = block.number - user_USDC[msg.sender].block_number;
            uint distance_per_day = distance / BLOCK_PER_DAY;
            uint distance_block = distance % BLOCK_PER_DAY;
            uint interest = total_borrow_USDC * pow(WAD + INTEREST_RATE, distance_per_day) - total_borrow_USDC;
            interest += total_borrow_USDC * pow(INTEREST_RATE_PER_BLOCK, distance_block) - total_borrow_USDC;
            _;
        }
    }

    function initializeLendingProtocol(address token) external payable {
        ERC20(token).transferFrom(msg.sender, address(this), msg.value);
    }

    function deposit(address token, uint256 amount) external payable {
        if (token == usdc) {
            require(0 < amount, "amount check");
            ERC20(token).transferFrom(msg.sender, address(this), amount);
            user_USDC[msg.sender].deposit_amount += amount;
            total_deposit_USDC += amount;
        } else {
            require(0 < msg.value && amount <= msg.value, "amount check");
            user_ETH[msg.sender].deposit_amount += amount;
            total_deposit_ETH += amount;
        }
        lender.push(msg.sender);
    }

    function borrow(address token, uint256 amount) external accrueInterest {
        require(total_deposit_USDC >= amount, "check amount");
        (uint256 eth_price, uint256 usdc_price) = token_price();
        uint256 max_borrow = calc_max_borrow(eth_price);
        uint256 possible_borrow = max_borrow - user_USDC[msg.sender].borrow_amount;

        require(amount <= possible_borrow, "amount check");


        ERC20(token).transfer(msg.sender, amount);
        total_borrow_ETH += amount;
        user_USDC[msg.sender].borrow_amount += amount;
        borrower.push(msg.sender);
    }

    function withdraw(address token, uint256 amount) external accrueInterest {
        require(user_ETH[msg.sender].deposit_amount >= amount, "check amount");
        uint256 total_debt = user_USDC[msg.sender].borrow_amount;

        if (0 < total_debt) {
            (uint256 eth_price, uint256 usdc_price) = token_price();
            uint256 remain_ETH_value = (user_ETH[msg.sender].deposit_amount - amount) * eth_price / 1 ether;
            uint256 borrow_USDC_value = total_debt * usdc_price / 1 ether;
            
            require(borrow_USDC_value * 100 <= remain_ETH_value * LT, "check amount");
        }

        payable(msg.sender).transfer(amount);
        total_deposit_ETH -= amount;
        user_ETH[msg.sender].deposit_amount -= amount;

    }

    function repay(address token, uint256 amount) external accrueInterest {
        uint256 total_debt = user_USDC[msg.sender].borrow_amount;
        require(total_debt >= amount, "check amount");
        user_USDC[msg.sender].borrow_amount -= amount;
        total_deposit_USDC += amount;
        ERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function liquidate(address target, address token, uint256 amount) external {
        (uint256 ethPrice, uint256 usdcPrice) = token_price();
        uint256 totalDebt = user_USDC[target].borrow_amount;
        
        require(totalDebt > 0, "No debt to liquidate");

        uint256 remainingETHValue = (user_ETH[target].deposit_amount * ethPrice) / 1 ether;
        require(totalDebt * 100 > remainingETHValue * LT, "Not eligible for liquidation");

        uint256 maxLiquidationAmount;
        if (totalDebt <= 100 ether) {
            maxLiquidationAmount = totalDebt;
        } else {
            maxLiquidationAmount = totalDebt / 4;
        }
        require(amount <= maxLiquidationAmount, "Exceeds max liquidation amount");

        uint256 amountValueInETH = (amount * usdcPrice) / ethPrice;
        require(amountValueInETH <= user_ETH[target].deposit_amount, "Insufficient collateral");

        user_USDC[target].borrow_amount -= amount;
        total_deposit_USDC += amount;
        user_ETH[target].deposit_amount -= amountValueInETH;

        ERC20(token).transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(amountValueInETH);

        remainingETHValue = (user_ETH[target].deposit_amount * ethPrice) / 1 ether;
        totalDebt = user_USDC[target].borrow_amount * usdcPrice / 1 ether;
        require(totalDebt * 100 <= remainingETHValue * LT, "Post-liquidation check failed");
    }

    function getAccruedSupplyAmount(address token) external accrueInterest returns (uint256) {
    }

    function token_price() internal returns (uint256, uint256) {
        uint256 ethPrice = price_oracle.getPrice(address(0x0));
        uint256 usdcPrice = price_oracle.getPrice(usdc);
        return (ethPrice, usdcPrice);
    }

    function calc_max_borrow(uint256 price) internal returns (uint256) {
        uint256 collateralValue = user_ETH[msg.sender].deposit_amount * price / 1 ether;
        return collateralValue * LTV / 100;
    }

    function pow(uint256 base, uint256 exponent) internal returns (uint256) {
        uint256 result = base;
        uint256 x = base;

        while (exponent != 0) {
            if (exponent % 2 != 0) {
                result = (result * x) / 1e18;
            }
            x = (x * x) / 1e18;
            exponent /= 2;
        }

        return result;
    }

}