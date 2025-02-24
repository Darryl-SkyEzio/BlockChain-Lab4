// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

// Define the contract
contract Money {
    uint money; // Create an integer variable money

    // Create a function to write money to the smart contract state variable
    function Deposit(uint _money) public {
        money = _money;
    }

    // Create a function to read money from the smart contract
    function Withdraw() public view returns (uint) {
        return money * 2;
    }
}
