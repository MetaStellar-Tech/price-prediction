// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "../../src/interfaces/IERC20.sol";

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public override totalSupply;
    mapping(address account => uint256) public override balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public override allowance;
    mapping(address account => bool) public blockedRecipient;
    uint256 public transferFeeBps;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function setBlockedRecipient(address account, bool blocked) external {
        blockedRecipient[account] = blocked;
    }

    function setTransferFeeBps(uint256 feeBps) external {
        require(feeBps <= 1_000, "fee too high");
        transferFeeBps = feeBps;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        allowance[from][msg.sender] = currentAllowance - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != address(0), "ERC20: transfer to zero");
        require(!blockedRecipient[to], "ERC20: recipient blocked");
        uint256 currentBalance = balanceOf[from];
        require(currentBalance >= amount, "ERC20: insufficient balance");
        balanceOf[from] = currentBalance - amount;
        uint256 fee = (amount * transferFeeBps) / 10_000;
        uint256 received = amount - fee;
        totalSupply -= fee;
        balanceOf[to] += received;
    }
}
