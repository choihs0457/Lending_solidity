// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/forge-std/src/console.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

contract UpsideAcademyLending {
    IPriceOracle public price_oracle;
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
    uint public INTEREST = 1;
    uint public dec = 10 ** 10;
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

        _;
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

}
function _calculateInterest(address _user) internal returns(uint) {
        uint distance = block.number.sub(userBalances[_user].blockNum);
        uint blockPerDay = distance.div(BLOCKS_PER_DAY);
        uint blockPerDayLast = distance % BLOCKS_PER_DAY;
        uint currentDebt = userBalances[_user].debt;
        uint compoundInterestDebt = _getCompoundInterest(currentDebt, INTEREST_RATE, blockPerDay);
        if (blockPerDayLast != 0) compoundInterestDebt += (_getCompoundInterest(compoundInterestDebt, INTEREST_RATE, 1).sub(compoundInterestDebt)).mul(blockPerDayLast).div(BLOCKS_PER_DAY);
        uint256 _compound = compoundInterestDebt.sub(currentDebt);
        userBalances[_user].debt = compoundInterestDebt;
        userBalances[_user].blockNum = block.number;
        return _compound;
    }
function _getCompoundInterest(uint256 p, uint256 r, uint256 n) internal pure returns (uint256) {
    uint256 rate = FixedPointMathLib.divWadUp(r, WAD) + FixedPointMathLib.WAD;
    return FixedPointMathLib.mulWadUp(p, rate.rpow(n, FixedPointMathLib.WAD));
}