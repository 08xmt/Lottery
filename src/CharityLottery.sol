//SPDX-License-Identifier: MIT
//@author 0xmt

pragma solidity ^0.8.24;

import {VRFSubscriptionManager} from "src/VRFSubscriptionManager.sol";

interface IERC20 {
    function transfer(address to, uint amount) external returns(bool);
    function transferFrom(address from, address to, uint amount) external returns(bool);
    function balanceOf(address) external returns(uint);
}

interface IERC4626 is IERC20 {
    function asset() external returns(address);
    function deposit(uint assets, address receiver) external returns(uint sharesReceived);
    function withdraw(uint assets, address receiver, address owner) external returns(uint sharesBurned);
}

contract CharityLottery is VRFSubscriptionManager{
    
    struct TicketIndex {
        uint start; //inclusive
        uint end; //exclusive
    }

    uint public totalSupply;
    uint public donations;
    IERC20 public immutable depositToken;
    IERC4626 public immutable vault;
    mapping(address => TicketIndex[]) public tickets; //user => TicketIndex(start, end) 
    uint public immutable period;
    uint public immutable jackpotChanceBps;
    mapping(uint => uint) public drawRequestId; //periodIndex => drawRequstId
    mapping(uint => uint) public lotDrawn; //periodIndex => lotDrawn
    bool public isDrawing;
    bool public jackpot;
    uint public jackpotLot;

    address charity;

    event Purchase(address purchaser, address indexed receiver, uint start, uint end);
    event Draw(uint indexed period, uint indexed lot, bool jackpot);
    event Jackpot(uint lot, uint prize);
    event Donation(uint amount);

    constructor(uint _period, uint _jackpotChanceBps, address _vrfCoordinator, address _vault, address _owner, address _charity) VRFSubscriptionManager(_vrfCoordinator, _owner) {
        require(_owner != address(0));
        require(_jackpotChanceBps > 0 && _jackpotChanceBps <= 10_000, "Jackpot chance out of bounds");
        period = _period;
        jackpotChanceBps = _jackpotChanceBps;
        depositToken = IERC20(IERC4626(_vault).asset());
        vault = IERC4626(_vault);
        charity = _charity;
        _createNewSubscription();
    }

    function purchaseTicket(uint amountIn) external {
        purchaseTicketTo(amountIn, msg.sender);
    }

    function purchaseTicketTo(uint amountIn, address receiver) public {
        require(!jackpot, "Jackpot has been hit");
        require(!isDrawing, "Draw in progress");
        depositToken.transferFrom(msg.sender, address(this), amountIn);
        tickets[receiver].push(TicketIndex(totalSupply, totalSupply + amountIn));
        totalSupply += amountIn;
        vault.deposit(amountIn, address(this));
        require(totalSupply * 10_000 < type(uint).max, "totalSupply exceed safe amount");
        emit Purchase(msg.sender, receiver, totalSupply - amountIn, totalSupply);
    }

    function donate(uint amount) external {
        depositToken.transferFrom(msg.sender, address(this), amount);
        donations += amount;
        emit Donation(amount);
    }

    function initiateDraw() external {
        require(period - block.timestamp % period > 120, "Cant draw in the last 120 seconds of a period");
        uint periodIndex = block.timestamp / period;
        require(drawRequestId[periodIndex] == 0, "Already drawn for this period");
        isDrawing = true;
        drawRequestId[periodIndex] = requestRandomWords();
    }
    
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        require(drawRequestId[block.timestamp / period] == requestId, "Wrong requestId");
        isDrawing = false;
        _draw(randomWords[0]);
    }

    function _draw(uint randomNumber) internal returns(uint lot){
        //Since tickets are 0 indexed, maxTicketNumber is one less than totalSupply
        uint maxTicketNumber = totalSupply - 1;
        //Adding duds to lot numbers, if a lot is drawn above max ticket number, there's no winner this drawing
        uint lotNumbers = maxTicketNumber * 10_000 / jackpotChanceBps;
        //Entropy upper bound is largest multiple of lotNumbers less than max randomNumber (2^256-1)
        uint randomNumberUpperBound = type(uint).max - type(uint).max % (type(uint).max / lotNumbers);

        //Get rid of modulo bias cheaply to make drawings completely fair
        while(randomNumber > randomNumberUpperBound){
            randomNumber = uint(keccak256(abi.encodePacked(randomNumber)));
        }

        uint periodIndex = block.timestamp / period;
        lot = randomNumber % lotNumbers;
        lotDrawn[periodIndex] = lot;
        if(lot < maxTicketNumber){
            jackpot = true;
            jackpotLot = lot;
            cancelSubscription(); //Cancel VRF Oracle subscription and send remaining funds to owner
            emit Jackpot(lot, maxTicketNumber + donations);
        }
        emit Draw(periodIndex, lot, jackpot);
    }

    function claimJackpot() external {
        for(uint i; i < tickets[msg.sender].length; i++){
            if(claimJackpotFor(i, msg.sender)) break;
        }
    }
    
    function claimJackpotFor(uint purchaseIndex, address winner) public returns(bool){
        require(jackpot, "Jackpot not hit");
        TicketIndex memory ticketIndex = tickets[winner][purchaseIndex];
        if(ticketIndex.start <= jackpotLot && ticketIndex.end > jackpotLot){
            //Withdraw winnings to winner
            vault.withdraw(totalSupply + donations, winner, address(this));
            //Send remaining vault supply to charity
            if(charity != address(0))
                vault.transfer(charity, vault.balanceOf(address(this)));
            else
                vault.transfer(owner, vault.balanceOf(address(this)));
            return true;
        }
        return false;
    }
}
