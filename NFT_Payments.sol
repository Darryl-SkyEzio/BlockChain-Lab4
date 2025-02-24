// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTBuyNowPayLater is ReentrancyGuard {
    // Use smaller, more focused structs to reduce stack depth
    struct NFTDetails {
        address nftContract;
        uint256 tokenId;
        bool isTransferred;
    }

    struct PaymentTerms {
        uint256 totalCost;
        uint256 paymentPerMonth;
        uint256 totalPayments;
        uint256 penaltyPercent;
        uint256 remainingAmount;
        uint256 remainingPayments;
        uint256 downPaymentAmount;
    }
    
    struct PaymentStatus {
        uint256 paymentDate;
        uint256 nextPaymentDate;
        uint256 missedPayments;
        bool isActive;
        uint256 planCreationTime;
    }

    struct Plan {
        address buyer;
        NFTDetails nftDetails;
        PaymentTerms terms;
        PaymentStatus status;
    }

    // Maps buyer address to plan ID
    mapping(address => uint256) public buyerToPlanId;
    // Maps plan ID to payment plan
    mapping(uint256 => Plan) public plans;
    uint256 public nextPlanId = 1;
    
    address public immutable seller;
    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 constant SECONDS_PER_MONTH = 30 * SECONDS_PER_DAY;

    mapping(string => uint256) private monthToNumber;

    // Enhanced events for better transaction monitoring
    event PlanCreated(
        uint256 indexed planId,
        address indexed buyer, 
        address indexed nftContract,
        uint256 tokenId,
        uint256 totalCost, 
        uint256 downPayment,
        uint256 monthlyPayment, 
        uint256 totalPayments,
        string startDate
    );
    
    event PaymentMade(
        uint256 indexed planId,
        address indexed buyer, 
        uint256 remainingPayments, 
        uint256 amountPaid, 
        uint256 remainingAmount,
        uint256 timestamp
    );
    
    event PenaltyApplied(
        uint256 indexed planId,
        address indexed buyer, 
        uint256 penaltyAmount
    );
    
    event PlanDefaulted(
        uint256 indexed planId,
        address indexed buyer, 
        uint256 amountForfeited,
        address nftContract,
        uint256 tokenId
    );
    
    event NFTPurchaseCompleted(
        uint256 indexed planId,
        address indexed buyer,
        address indexed nftContract,
        uint256 tokenId,
        uint256 finalPaymentAmount,
        uint256 totalPaid
    );

    constructor() {
        seller = msg.sender;
        _initializeMonthMap();
    }

    // Separate initialization to reduce constructor complexity
    function _initializeMonthMap() private {
        monthToNumber["January"] = 1;
        monthToNumber["February"] = 2;
        monthToNumber["March"] = 3;
        monthToNumber["April"] = 4;
        monthToNumber["May"] = 5;
        monthToNumber["June"] = 6;
        monthToNumber["July"] = 7;
        monthToNumber["August"] = 8;
        monthToNumber["September"] = 9;
        monthToNumber["October"] = 10;
        monthToNumber["November"] = 11;
        monthToNumber["December"] = 12;
    }

    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can perform this action");
        _;
    }

    // Step 1: Create plan - only validate inputs
    function createNFTPaymentPlan(
        address buyer,
        address _nftContract,
        uint256 _tokenId,
        uint256 _totalCost,
        uint256 _downPaymentPercent,
        uint256 _totalPayments,
        uint256 _penaltyPercent
    ) external onlySeller returns (uint256) {
        // Basic validation
        require(_totalCost > 0, "Total cost must be greater than 0");
        require(_totalPayments > 0, "Number of payments must be greater than 0");
        require(_penaltyPercent <= 100, "Penalty percentage must be <= 100");
        require(_downPaymentPercent <= 100, "Down payment percentage must be <= 100");
        require(buyerToPlanId[buyer] == 0, "Buyer already has an active plan");
        
        // Calculate financial terms
        uint256 downPayment = (_totalCost * _downPaymentPercent) / 100;
        uint256 remainingAmount = _totalCost - downPayment;
        uint256 monthlyPayment = remainingAmount / _totalPayments;
        
        require(monthlyPayment * _totalPayments == remainingAmount, "Remaining amount must be evenly divisible");
        
        // Create plan ID
        uint256 planId = nextPlanId++;
        buyerToPlanId[buyer] = planId;
        
        // Initialize NFT details
        plans[planId].buyer = buyer;
        plans[planId].nftDetails = NFTDetails({
            nftContract: _nftContract,
            tokenId: _tokenId,
            isTransferred: false
        });
        
        // Initialize payment terms
        plans[planId].terms = PaymentTerms({
            totalCost: _totalCost,
            paymentPerMonth: monthlyPayment,
            totalPayments: _totalPayments,
            penaltyPercent: _penaltyPercent,
            remainingAmount: remainingAmount,
            remainingPayments: _totalPayments,
            downPaymentAmount: downPayment
        });
        
        // Initialize status (payment dates set in separate function)
        plans[planId].status = PaymentStatus({
            paymentDate: 0,
            nextPaymentDate: 0,
            missedPayments: 0,
            isActive: true,
            planCreationTime: block.timestamp
        });
        
        return planId;
    }
    
    // Step 2: Set payment dates (called after plan creation)
    function setPaymentDates(
        uint256 _planId,
        uint256 _startDay,
        string calldata _startMonth,
        uint256 _startYear
    ) external onlySeller {
        require(_planId > 0 && _planId < nextPlanId, "Invalid plan ID");
        require(plans[_planId].status.isActive, "Plan is not active");
        require(plans[_planId].status.nextPaymentDate == 0, "Payment dates already set");
        require(monthToNumber[_startMonth] != 0, "Invalid month name");
        
        uint256 startTimestamp = calculateTimestamp(_startDay, _startMonth, _startYear);
        require(startTimestamp > block.timestamp, "Start date must be in the future");
        
        // Set payment dates
        plans[_planId].status.paymentDate = _startDay;
        plans[_planId].status.nextPaymentDate = startTimestamp;
        
        // Now emit the plan created event
        Plan storage plan = plans[_planId];
        emit PlanCreated(
            _planId,
            plan.buyer,
            plan.nftDetails.nftContract,
            plan.nftDetails.tokenId,
            plan.terms.totalCost,
            plan.terms.downPaymentAmount,
            plan.terms.paymentPerMonth,
            plan.terms.totalPayments,
            formatDate(_startDay, _startMonth, _startYear)
        );
    }

    function calculateTimestamp(uint256 day, string memory month, uint256 year) internal view returns (uint256) {
        require(day > 0 && day <= 31, "Invalid day");
        require(year >= 2024, "Invalid year");
        
        uint256 monthNum = monthToNumber[month];
        require(monthNum != 0, "Invalid month");
        
        // Validation for days in month
        if (monthNum == 2) {
            bool isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
            require(day <= (isLeapYear ? 29 : 28), "Invalid day for February");
        } else if (monthNum == 4 || monthNum == 6 || monthNum == 9 || monthNum == 11) {
            require(day <= 30, "Invalid day for this month");
        }

        // Simple timestamp approximation
        return ((year - 1970) * 365 + ((year - 1969) / 4)) * SECONDS_PER_DAY + 
               ((monthNum - 1) * 30 * SECONDS_PER_DAY) + 
               ((day - 1) * SECONDS_PER_DAY);
    }

    function formatDate(uint256 day, string memory month, uint256 year) internal pure returns (string memory) {
        return string(abi.encodePacked(
            uint2str(day),
            " ",
            month,
            " ",
            uint2str(year)
        ));
    }

    // Process down payment and lock NFT in escrow
    function processDownPayment(uint256 planId) external payable nonReentrant {
        require(planId > 0 && planId < nextPlanId, "Invalid plan ID");
        Plan storage plan = plans[planId];
        
        require(plan.buyer == msg.sender, "Only the buyer can make payments");
        require(plan.status.isActive, "No active payment plan");
        require(plan.terms.downPaymentAmount > 0, "Down payment already processed");
        require(plan.status.nextPaymentDate > 0, "Payment dates not set");
        
        require(msg.value >= plan.terms.downPaymentAmount, "Insufficient down payment amount");

        // Transfer NFT to contract (escrow)
        IERC721 nftContract = IERC721(plan.nftDetails.nftContract);
        
        // Verify NFT ownership and approval
        require(
            nftContract.ownerOf(plan.nftDetails.tokenId) == seller,
            "Seller does not own the NFT"
        );
        
        require(
            nftContract.isApprovedForAll(seller, address(this)) ||
            nftContract.getApproved(plan.nftDetails.tokenId) == address(this),
            "Contract not approved to transfer NFT"
        );
        
        // Transfer NFT to contract for escrow
        nftContract.transferFrom(seller, address(this), plan.nftDetails.tokenId);
        
        // Process down payment
        plan.terms.downPaymentAmount = 0; // Mark as processed
        
        // Transfer payment to seller
        payable(seller).transfer(msg.value);
        
        // Emit down payment event
        emit PaymentMade(
            planId,
            msg.sender,
            plan.terms.remainingPayments,
            msg.value,
            plan.terms.remainingAmount,
            block.timestamp
        );
    }

    // Make regular payment
    function makePayment(uint256 planId) external payable nonReentrant {
        require(planId > 0 && planId < nextPlanId, "Invalid plan ID");
        Plan storage plan = plans[planId];
        
        require(plan.buyer == msg.sender, "Only the buyer can make payments");
        require(plan.status.isActive, "No active payment plan");
        require(plan.terms.remainingAmount > 0, "Plan is already completed");

        uint256 requiredPayment = plan.terms.paymentPerMonth;
        uint256 penaltyAmount = 0;

        if (block.timestamp > plan.status.nextPaymentDate) {
            plan.status.missedPayments++;
            penaltyAmount = (plan.terms.remainingAmount * plan.terms.penaltyPercent) / 100;
            requiredPayment += penaltyAmount;

            if (plan.status.missedPayments >= 3) {
                uint256 forfeited = plan.terms.totalCost - plan.terms.remainingAmount;
                plan.status.isActive = false;
                
                emit PlanDefaulted(
                    planId,
                    msg.sender,
                    forfeited,
                    plan.nftDetails.nftContract,
                    plan.nftDetails.tokenId
                );
                
                revert("Plan defaulted - three payments missed");
            }
        }

        require(msg.value >= requiredPayment, "Insufficient payment amount");

        // Update payment status
        _processPayment(planId, msg.value, penaltyAmount);
        
        // Transfer payment to seller
        payable(seller).transfer(msg.value);
    }
    
    // Helper to process payment updates
    function _processPayment(uint256 planId, uint256 paymentAmount, uint256 penaltyAmount) private {
        Plan storage plan = plans[planId];
        
        // Update plan status
        plan.terms.remainingAmount -= plan.terms.paymentPerMonth;
        plan.terms.remainingPayments--;
        
        // Calculate next payment date
        _updateNextPaymentDate(planId);
        
        if (penaltyAmount > 0) {
            emit PenaltyApplied(planId, plan.buyer, penaltyAmount);
        }

        emit PaymentMade(
            planId,
            plan.buyer,
            plan.terms.remainingPayments,
            paymentAmount,
            plan.terms.remainingAmount,
            block.timestamp
        );

        // Check if plan is completed
        if (plan.terms.remainingAmount == 0) {
            _completePlan(planId);
        }
    }
    
    // Update next payment date
    function _updateNextPaymentDate(uint256 planId) private {
        Plan storage plan = plans[planId];
        
        // Calculate next payment date keeping the same day of month
        uint256 currentYear = (plan.status.nextPaymentDate / (365 * SECONDS_PER_DAY)) + 1970;
        uint256 currentMonth = ((plan.status.nextPaymentDate % (365 * SECONDS_PER_DAY)) / (30 * SECONDS_PER_DAY)) + 1;
        
        currentMonth += 1;
        if (currentMonth > 12) {
            currentMonth = 1;
            currentYear += 1;
        }
        
        plan.status.nextPaymentDate = calculateTimestamp(
            plan.status.paymentDate,
            monthToString(currentMonth),
            currentYear
        );
    }
    
    // Complete plan and transfer NFT
    function _completePlan(uint256 planId) private {
        Plan storage plan = plans[planId];
        plan.status.isActive = false;
        
        // Transfer NFT to buyer if final payment
        if (!plan.nftDetails.isTransferred) {
            // Attempt to transfer the NFT
            try IERC721(plan.nftDetails.nftContract).transferFrom(
                address(this), 
                plan.buyer,
                plan.nftDetails.tokenId
            ) {
                plan.nftDetails.isTransferred = true;
                
                emit NFTPurchaseCompleted(
                    planId,
                    plan.buyer,
                    plan.nftDetails.nftContract,
                    plan.nftDetails.tokenId,
                    plan.terms.paymentPerMonth,
                    plan.terms.totalCost
                );
            } catch {
                // Failed to transfer NFT
                revert("NFT transfer failed - contact seller");
            }
        }
    }
    
    function monthToString(uint256 month) internal pure returns (string memory) {
        if (month == 1) return "January";
        if (month == 2) return "February";
        if (month == 3) return "March";
        if (month == 4) return "April";
        if (month == 5) return "May";
        if (month == 6) return "June";
        if (month == 7) return "July";
        if (month == 8) return "August";
        if (month == 9) return "September";
        if (month == 10) return "October";
        if (month == 11) return "November";
        if (month == 12) return "December";
        return "Invalid Month";
    }

    function getPlanDetails(uint256 planId) external view returns (
        address buyer,
        address nftContract,
        uint256 tokenId,
        uint256 totalCost,
        uint256 monthlyPayment,
        uint256 remainingAmount,
        uint256 nextPaymentDueTimestamp,
        uint256 remainingPayments,
        uint256 missedPayments,
        bool isActive,
        bool isNFTTransferred
    ) {
        Plan storage plan = plans[planId];
        
        return (
            plan.buyer,
            plan.nftDetails.nftContract,
            plan.nftDetails.tokenId,
            plan.terms.totalCost,
            plan.terms.paymentPerMonth,
            plan.terms.remainingAmount,
            plan.status.nextPaymentDate,
            plan.terms.remainingPayments,
            plan.status.missedPayments,
            plan.status.isActive,
            plan.nftDetails.isTransferred
        );
    }
    
    // Get buyer's plan ID
    function getBuyerPlanId(address buyer) external view returns (uint256) {
        return buyerToPlanId[buyer];
    }
    
    // Emergency function to release NFT if contract has issues
    function emergencyReleaseNFT(uint256 planId, address to) external onlySeller {
        Plan storage plan = plans[planId];
        require(!plan.nftDetails.isTransferred, "NFT already transferred");
        
        IERC721(plan.nftDetails.nftContract).transferFrom(
            address(this),
            to,
            plan.nftDetails.tokenId
        );
        
        plan.nftDetails.isTransferred = true;
    }

    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        return string(bstr);
    }
}