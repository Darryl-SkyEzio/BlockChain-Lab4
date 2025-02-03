// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// Import OpenZeppelin's Ownable and ReentrancyGuard contracts
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract BonusAllocator is Ownable, ReentrancyGuard {
    struct Investor {
        address addr;
        uint investmentAmount;
    }

    Investor[] public investors;

    mapping(address => bool) public bonusesPaidOut; // Tracks whether a bonus has been paid to an investor

    uint constant public BONUS_THRESHOLD = 1000; // Investment threshold for higher bonus
    uint constant public BASE_BONUS_PERCENTAGE = 5; // 5%
    uint constant public HIGH_BONUS_PERCENTAGE = 10; // 10%

    // Event to track when a new investor is added
    event InvestorAdded(address indexed addr, uint investmentAmount);

    // Event to track when bonuses are allocated
    event BonusAllocated(address indexed addr, uint bonusAmount);

    // Event to track when Ether is withdrawn
    event Withdrawal(address indexed owner, uint amount);

    // Constructor to initialize contract and ownership
    constructor() payable Ownable(msg.sender) {}

    mapping(address => bool) public isInvestor;

    function addInvestor(address _addr, uint _investmentAmount) public onlyOwner {
        require(_addr != address(0), "Invalid address");
        require(_investmentAmount > 0, "Investment amount must be greater than 0");
        require(!isInvestor[_addr], "Investor already exists");

        investors.push(Investor(_addr, _investmentAmount));
        isInvestor[_addr] = true; // Mark as an investor

        emit InvestorAdded(_addr, _investmentAmount);
    }

    // Allocate bonuses (restricted to onlyOwner, with reentrancy guard)
    function allocateBonuses() public onlyOwner nonReentrant {
        for (uint i = 0; i < investors.length; i++) {
            address investorAddress = investors[i].addr;

            // Check if the bonus has already been paid
            require(!bonusesPaidOut[investorAddress], "Bonus already paid");

            uint bonusPercentage = BASE_BONUS_PERCENTAGE;

            // Determine bonus percentage based on investment amount
            if (investors[i].investmentAmount > BONUS_THRESHOLD) {
                bonusPercentage = HIGH_BONUS_PERCENTAGE;
            }

            uint bonusAmount = (investors[i].investmentAmount * bonusPercentage) / 100;

            // Transfer the bonus (ensure the contract holds enough ETH to transfer)
            payable(investorAddress).transfer(bonusAmount);

            // Mark the bonus as paid
            bonusesPaidOut[investorAddress] = true;

            // Emit an event to log the bonus allocation
            emit BonusAllocated(investorAddress, bonusAmount);
        }
    }

    // Allow the contract to receive ETH for bonus payments
    receive() external payable {}

    // Withdraw function to allow owner to withdraw entire contract balance
    function withdraw() public onlyOwner nonReentrant {
        uint balance = address(this).balance;
        require(balance > 0, "No Ether available for withdrawal");

        // Transfer the balance to the owner
        payable(owner()).transfer(balance);

        // Emit an event to log the withdrawal
        emit Withdrawal(owner(), balance);
    }

    // Helper function to check the contract balance
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

        // Event to track when an investor is removed
    event InvestorRemoved(address indexed addr, uint investmentAmount);

    function removeInvestor(uint index) public onlyOwner {
        require(index < investors.length, "Index out of bounds");

        address investorAddress = investors[index].addr;
        uint investmentAmount = investors[index].investmentAmount;

        isInvestor[investorAddress] = false; // Mark as removed

        investors[index] = investors[investors.length - 1];
        investors.pop();

        emit InvestorRemoved(investorAddress, investmentAmount);
    }

    function getInvestorsCount() public view returns (uint) {
    return investors.length;
}
}