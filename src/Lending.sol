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

    struct User_account {
        uint256 USDC_deposit;                  // 유저의 USDC 예치금
        uint256 USDC_deposit_block;            // 유저의 USDC 예치를 마지막으로 진행한 블록
        uint256 USDC_borrow;                   // 유저의 USDC 대출금
        uint256 USDC_borrow_block;             // 유저의 USDC 대출을 마지막으로 진행한 블록
        uint256 ETH_deposit;                   // 유저의 ETH 예치금
        uint256 ETH_deposit_block;             // 유저의 ETH 예치를 마지막으로 진행한 블록
        uint256 ETH_borrow;                    // 유저의 ETH 대출금
        uint256 ETH_borrow_block;              // 유저의 ETH 대출을 마지막으로 진행한 블록
        uint256 update_slot;                   // 유저가 마지막으로 업데이트한 update_list의 슬롯
    }

    struct Update {
        uint256 block_number;                  // 이자 계산을 위한 해당 블록의 넘버
        uint256 USDC_total_borrow;             // 해당 블록에서 유저들이 빌려간 USDC
        uint256 USDC_total_deposit;            // 해당 블록에서 유저들이 예치한 USDC
        uint256 USDC_total_repay;              // 해당 블록에서 반환한 총 USDC
        uint256 USDC_total_withdraw;           // 해당 블록에서 인출한 총 USDC
        uint256 USDC_cached_total_deposit;     // 이전 블록까지 예치된 총 USDC
        uint256 USDC_cached_total_borrow;      // 이전 블록까지 빌려간 총 USDC
        uint256 USDC_cached_interest;          // 이전 블록에서 해당 블록까지의 USDC 이자
        uint256 ETH_total_borrow;              // 해당 블록에서 유저들이 빌려간 ETH
        uint256 ETH_total_deposit;             // 해당 블록에서 유저들이 예치한 ETH
        uint256 ETH_total_repay;               // 해당 블록에서 반환한 총 ETH
        uint256 ETH_total_withdraw;            // 해당 블록에서 인출한 총 ETH
        uint256 ETH_cached_total_deposit;      // 이전 블록까지 예치된 총 ETH
        uint256 ETH_cached_total_borrow;       // 이전 블록까지 빌려간 총 ETH
        uint256 ETH_cached_interest;           // 이전 블록에서 해당 블록까지의 ETH 이자
    }

    struct Block_info{
        bool init;                             // 해당 블록에 다른 유저가 행위를 했는지
        uint256 slot;                          // update_list 몇번째 슬롯에 있는지
    }
    
    event LogEvent(uint256 message);
    uint256 LT = 75;
    uint256 LTV = 50;
    uint256 INTEREST = 1e15;
    uint256 block_per_day = 7200;
    uint256 block_interest = 1000000138822311089;

    Update[] public update_list;
    mapping (uint256 => Block_info) block_info;
    mapping (address => bool) user_init;
    mapping (address => User_account) account;

    constructor(IPriceOracle upsideOracle, address token) {
        price_oracle = upsideOracle;
        usdc = token;
    }

    modifier only_user(){
        require(user_init[msg.sender], "non user");
        _;
    }

    modifier update_state(address target) {
        if (update_list.length < 2){
            _;
        }
        uint256 start = account[target].update_slot;
        start == 0 ? start + 1 : start;
        for (uint256 i = start; i < update_list.length; i++) {
            if (update_list[i].block_number < block.number) {
                // emit LogEvent(update_list[i].ETH_cached_interest);
                // emit LogEvent(account[target].ETH_deposit);
                // emit LogEvent(update_list[i].ETH_cached_total_deposit);
                // emit LogEvent(message);
                if(update_list[i].ETH_cached_total_deposit > 0) {
                    account[target].ETH_deposit += update_list[i].ETH_cached_interest * account[target].ETH_deposit / update_list[i].ETH_cached_total_deposit;
                    account[target].ETH_borrow += update_list[i].ETH_cached_interest * account[target].ETH_borrow / update_list[i].ETH_cached_total_borrow;
                }
                if(update_list[i].USDC_cached_total_deposit > 0) {
                    account[target].USDC_deposit += update_list[i].USDC_cached_interest * account[target].USDC_deposit / update_list[i].USDC_cached_total_deposit;
                    account[target].USDC_borrow +=  update_list[i].USDC_cached_interest * account[target].USDC_borrow / update_list[i].USDC_cached_total_borrow;
                }
                account[target].update_slot = i;
            }
        }
    }

    function initializeLendingProtocol(address token) external payable {
        ERC20(token).transferFrom(msg.sender, address(this), msg.value);
        update_list.push();
    }

    function deposit(address token, uint256 amount) update_state(msg.sender) external payable {
        User_account memory user_account;
        Update memory update;
        (user_account, update) = setting(msg.sender);
        if (token == usdc) {
            usdc_deposit(user_account, update , amount);
        } else {
            ether_deposit(user_account, update , amount);
        }
        user_init[msg.sender] = true;
    }

    function borrow(address token, uint256 amount) update_state(msg.sender) external {
        User_account memory user_account;
        Update memory update;
        (user_account, update) = setting(msg.sender);
        (uint256 eth_price, uint256 usdc_price) = token_price();
        if (token == usdc) {
            usdc_borrow(user_account, update , amount, eth_price, usdc_price);
        } else {
            ether_borrow(user_account, update , amount, eth_price, usdc_price);
        }
    }

    function withdraw(address token, uint256 amount) update_state(msg.sender) external {
        User_account memory user_account;
        Update memory update;
        (user_account, update) = setting(msg.sender);
        (uint256 eth_price, uint256 usdc_price) = token_price();
        if (token == usdc) {
            usdc_withdraw(user_account, update , amount, eth_price, usdc_price);
        } else {
            ether_withdraw(user_account, update , amount, eth_price, usdc_price);
        }
    }

    function repay(address token, uint256 amount) update_state(msg.sender) external {
        User_account memory user_account;
        Update memory update;
        (user_account, update) = setting(msg.sender);
        if (token == usdc) {
            usdc_repay(user_account, update , amount);
        } else {
            ether_repay(user_account, update , amount);
        }
    }

    function liquidate(address target, address token, uint256 amount) update_state(target) external {
        User_account memory user_account;
        Update memory update;
        (user_account, update) = setting(target);
        if (token == usdc) {
            usdc_liqudate(user_account, update , target, amount);
        } else {
            ether_liqudate(user_account, update, target, amount);
        }
    }

    function getAccruedSupplyAmount(address token) external returns (uint256) {
        if (token == usdc) {
            return account[msg.sender].USDC_deposit ;
        } else {
            return account[msg.sender].ETH_deposit ;
        }
    }

    function pow(uint256 base, uint256 exp) public  returns (uint256) {
        uint256 result = 1;
        while (exp > 0) {
            if (exp % 2 == 1) {
                result = rmul(result , base);
            }
            base = rmul(base, base);
            exp /= 2;
        }
        return result;
    }

    function rmul(uint x, uint y) public  returns (uint256) {
        return (x * y) / 1 ether;
    }

    function token_price() internal returns (uint256, uint256) {
        uint256 eth_price = price_oracle.getPrice(address(0x0));
        uint256 usdc_price = price_oracle.getPrice(usdc);
        return (eth_price, usdc_price);
    }


    function setting(address target) internal returns(User_account memory user_account, Update memory update) {
        if (user_init[target]){
            user_account = account[target];
        } else {
            user_init[target] = true;
        }
        if (block_info[block.number].init){
            update = update_list[block_info[block.number].slot];
        } else {
            update_list.push();
            block_info[block.number].init = true;
            block_info[block.number].slot = update_list.length - 1;
            Update memory before_update = update_list[update_list.length - 2];
            update = list_update(before_update);
            update_list[update_list.length - 1] = update;
        }
    }

    function func_update(User_account memory user_account, Update memory update, address target) internal {
        account[target] = user_account;
        update_list[block_info[block.number].slot] = update;
    }

    function list_update(Update memory target) internal returns(Update memory new_update){
        new_update = cal_interest(target);
        new_update.ETH_cached_total_borrow = target.ETH_total_borrow + target.ETH_cached_total_borrow - target.ETH_total_repay + target.ETH_cached_interest;
        new_update.ETH_cached_total_deposit = target.ETH_total_deposit + target.ETH_cached_total_deposit  - target.ETH_total_withdraw + target.ETH_cached_interest;
        new_update.USDC_cached_total_borrow = target.USDC_total_borrow + target.USDC_cached_total_borrow - target.USDC_total_repay + target.USDC_cached_interest;
        new_update.USDC_cached_total_deposit = target.USDC_total_deposit + target.USDC_cached_total_deposit  - target.USDC_total_withdraw + target.USDC_cached_interest;
        new_update.block_number = block.number;
    }

    function cal_interest(Update memory update) internal returns(Update memory new_update) {
        uint256 distance = block.number - update.block_number;
        uint256 blockPerDay = distance / block_per_day;
        uint256 blockPerDayLast = distance % block_per_day;
        uint256 current_eth_Debt = update.ETH_cached_total_borrow;
        uint256 eth_interest = current_eth_Debt * pow((1 ether + INTEREST), blockPerDay) / 1 ether - current_eth_Debt;
        if (blockPerDayLast != 0) {
            eth_interest += current_eth_Debt * pow(block_interest, blockPerDayLast) - current_eth_Debt;
        }
        emit LogEvent(blockPerDay);
        new_update.ETH_cached_interest = eth_interest;

        uint256 current_usdc_Debt = update.USDC_cached_total_borrow;
        uint256 usdc_interest = current_usdc_Debt * pow((1 ether + INTEREST), blockPerDay) / 1 ether - current_usdc_Debt;
        if (blockPerDayLast != 0) {
            usdc_interest += current_usdc_Debt * pow(block_interest, blockPerDayLast) - current_usdc_Debt;
        }
        update.USDC_cached_interest = usdc_interest;
        new_update = update;
    }

    function ether_deposit(User_account memory user_account, Update memory update , uint256 amount) internal{
        require(0 < msg.value && amount <= msg.value, "amount check");
        user_account.ETH_deposit += amount;
        user_account.ETH_deposit_block = block.number;
        update.ETH_total_deposit += amount;
        func_update(user_account, update, msg.sender);
    }

    function usdc_deposit(User_account memory user_account, Update memory update , uint256 amount) internal{
        require(0 < amount, "amount check");
        user_account.USDC_deposit += amount;
        user_account.USDC_deposit_block += block.number;
        update.USDC_total_deposit += amount;
        func_update(user_account, update , msg.sender);
        ERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    function usdc_borrow(User_account memory user_account, Update memory update , uint256 amount, uint256  eth_price, uint256 usdc_price) internal {
        uint256 total_diposit = update.USDC_cached_total_deposit + update.USDC_total_deposit;
        uint256 total_borrow = update.USDC_cached_total_borrow + update.USDC_total_borrow;
        require(total_diposit - total_borrow >= amount, "check amount");
        uint256 collateralvalue = (user_account.ETH_deposit) / 1 ether * eth_price;
        uint256 collateral_value_to_loan = collateralvalue * LTV / 100;
        uint256 loanvalue = (user_account.USDC_borrow) / 1 ether * usdc_price;
        uint256 max_loan = collateral_value_to_loan - loanvalue;

        require(max_loan >= amount, "check amount");
        update.USDC_total_borrow += amount;
        user_account.USDC_borrow += amount;
        user_account.USDC_borrow_block = block.number;
        func_update(user_account, update, msg.sender);
        ERC20(usdc).transfer(msg.sender, amount);
    }

    function ether_borrow(User_account memory user_account, Update memory update , uint256 amount, uint256  eth_price, uint256 usdc_price) internal {
        uint256 total_diposit = update.ETH_cached_total_deposit + update.ETH_total_deposit;
        uint256 total_borrow = update.ETH_cached_total_borrow + update.ETH_total_borrow;
        require(total_diposit - total_borrow >= amount, "check amount");
        uint256 collateralvalue = (user_account.USDC_deposit) / 1 ether * usdc_price;
        uint256 collateral_value_to_loan = collateralvalue * LTV / 100;
        uint256 loanvalue = (user_account.ETH_borrow) / 1 ether * eth_price;
        uint256 max_loan = collateral_value_to_loan - loanvalue;

        require(max_loan >= amount, "check amount");
        update.ETH_total_borrow += amount;
        user_account.ETH_borrow += amount;
        user_account.ETH_borrow_block = block.number;
        func_update(user_account, update, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    function usdc_repay(User_account memory user_account, Update memory update , uint256 amount) internal {
        require(user_account.USDC_borrow >= amount, "check amount");
        user_account.USDC_borrow -= amount;
        update.USDC_total_repay += amount;
        func_update(user_account, update, msg.sender);
        ERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    function ether_repay(User_account memory user_account, Update memory update , uint256 amount) internal {
        require(user_account.ETH_borrow >= amount, "check amount");
        user_account.ETH_borrow -= amount;
        update.ETH_total_repay += amount;
        func_update(user_account, update, msg.sender);
    }

    function usdc_withdraw(User_account memory user_account, Update memory update , uint256 amount, uint256  eth_price, uint256 usdc_price) internal {
        uint256 total_debt = user_account.ETH_borrow;

        if (0 < total_debt) {
            uint256 collateral_value = (user_account.USDC_deposit - amount) * eth_price / 1 ether;
            uint256 total_debt_value = total_debt * eth_price / 1 ether;
            require(total_debt_value * 100 <= collateral_value * LT, "check amount");
        }

        update.ETH_total_withdraw += amount;
        user_account.ETH_deposit -= amount;
        func_update(user_account, update, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    function ether_withdraw(User_account memory user_account, Update memory update , uint256 amount, uint256  eth_price, uint256 usdc_price) internal {
        uint256 total_debt = user_account.USDC_borrow;

        if (0 < total_debt) {
            uint256 collateral_value = (user_account.ETH_deposit - amount) * eth_price / 1 ether;
            uint256 total_debt_value = total_debt * usdc_price / 1 ether;
            require(total_debt_value * 100 <= collateral_value * LT, "check amount");
        }

        update.ETH_total_withdraw += amount;
        user_account.ETH_deposit -= amount;
        func_update(user_account, update, msg.sender);
        payable(msg.sender).transfer(amount);
    }

    function usdc_liqudate(User_account memory user_account, Update memory update , address target, uint256 amount) public {
        (uint256 eth_price, uint256 usdc_price) = token_price();
        
        uint256 totalDebt = user_account.USDC_borrow;
        require(totalDebt > 0, "No debt to liquidate");

        uint256 collateralvalue_eth = (user_account.ETH_deposit * eth_price) / 1 ether;
        uint256 totalDebt_value = user_account.USDC_borrow * usdc_price / 1 ether;
        require(totalDebt_value * 100 >= collateralvalue_eth * LT, "Loan healthy");

        uint256 max_liquidation;
        if (totalDebt <= 100 ether) {
            max_liquidation = totalDebt;
        } else {
            max_liquidation = totalDebt / 4;
        }
        require(amount <= max_liquidation, "Exceeds max liquidation amount");

        require(user_account.USDC_borrow > amount, "amount check plz");


        uint256 collateralToSeize = (amount * usdc_price) / eth_price;
        require(collateralToSeize <= user_account.ETH_deposit, "collateral check");

        user_account.USDC_borrow -= amount;
        update.USDC_total_repay += amount;
        user_account.ETH_deposit -= collateralToSeize;
        update.ETH_total_withdraw += collateralToSeize;

        func_update(user_account, update, target);
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(collateralToSeize);

    }

    function ether_liqudate(User_account memory user_account, Update memory update , address target, uint256 amount) internal {
        (uint256 eth_price, uint256 usdc_price) = token_price();
        
        uint256 totalDebt = user_account.ETH_borrow;
        require(totalDebt > 0, "No debt to liquidate");

        uint256 collateralvalue_USDC = (user_account.USDC_deposit * usdc_price) / 1 ether;
        uint256 totalDebt_value = user_account.ETH_borrow * eth_price / 1 ether;
        require(totalDebt_value * 100 >= collateralvalue_USDC * LT, "Loan healthy");

        uint256 max_liquidation;
        if (totalDebt <= 100 ether) {
            max_liquidation = totalDebt;
        } else {
            max_liquidation = totalDebt / 4;
        }
        require(amount <= max_liquidation, "Exceeds max liquidation amount");

        require(user_account.ETH_borrow > amount, "amount check plz");


        uint256 collateralToSeize = (amount * eth_price) / usdc_price;
        require(collateralToSeize <= user_account.USDC_deposit, "collateral check");

        user_account.ETH_borrow -= amount;
        update.ETH_total_repay += amount;
        user_account.USDC_deposit -= collateralToSeize;
        update.USDC_total_withdraw += collateralToSeize;

        func_update(user_account, update, target);
        ERC20(usdc).transfer(msg.sender, collateralToSeize);

    }
}