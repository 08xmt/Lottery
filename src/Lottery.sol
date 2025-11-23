pragma solidity ^0.8.24;

import {VRFSubscriptionManager} from "src/VRFSubscriptionManager.sol";

interface IERC20 {
    function transfer(address to, uint amount) external returns(bool);
    function transferFrom(address from, address to, uint amount) external returns(bool);
    function balanceOf(address) external returns(uint);
}

contract Lottery is VRFSubscriptionManager{
    
    struct TicketIndex {
        uint start; //inclusive
        uint end; //exclusive
    }

    uint public totalSupply;
    IERC20 public depositToken;
    mapping(address => TicketIndex[]) public tickets;
    uint public period;
    uint public jackpotChanceBps;
    mapping(uint => uint) public drawRequestId;
    mapping(uint => uint) public lotDrawn;
    bool public jackpot;
    uint public jackpotLot;

    event Purchase(address purchaser, address indexed receiver, uint start, uint end);
    event Draw(uint indexed period, uint indexed lot, bool jackpot);
    event Jackpot(uint lot, uint prize);

    constructor(uint _period, uint _jackpotChanceBps, address _vrfCoordinator, address _depositToken, address _owner) VRFSubscriptionManager(_vrfCoordinator, _owner) {
        period = _period;
        jackpotChanceBps = _jackpotChanceBps;
        depositToken = IERC20(_depositToken);
        _createNewSubscription();
    }

    function purchaseTicket(uint amountIn) external {
        purchaseTicketTo(amountIn, msg.sender);
    }

    function purchaseTicketTo(uint amountIn, address receiver) public {
        require(!jackpot, "Jackpot has been hit");
        depositToken.transferFrom(msg.sender, address(this), amountIn);
        tickets[receiver].push(TicketIndex(totalSupply, totalSupply + amountIn)); //Todo: Check if need to +1
        totalSupply += amountIn;
        require(totalSupply * 10_000 < type(uint).max, "totalSupply exceed safe amount");
        emit Purchase(msg.sender, receiver, totalSupply - amountIn, totalSupply);
    }

    function initiateDraw() external {
        require(drawRequestId[block.timestamp % period] == 0, "Already drawn for this period");
        drawRequestId[block.timestamp % period] = requestRandomWords();
    }
    
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        require(drawRequestId[block.timestamp % period] == requestId, "Wrong requestId");
        _draw(randomWords[0]);
    }

    function _draw(uint entropy) internal returns(uint lot){
        uint lotNumbers = totalSupply * 10_000 / jackpotChanceBps;
        uint entropyUpperBound = type(uint).max / lotNumbers;

        //Get rid of modulo bias (very cheap)
        while(entropy > entropyUpperBound){
            entropy = uint(keccak256(abi.encodePacked(entropy)));
        }

        lot = entropy % lotNumbers;
        lotDrawn[block.timestamp % period] = lot;
        if(lot < totalSupply){
            jackpot = true;
            jackpotLot = lot;
            cancelSubscription();
            emit Jackpot(lot, depositToken.balanceOf(address(this)));
        }
        emit Draw(block.timestamp % period, lot, jackpot);
    }

    function claimJackpot() external {
        for(uint i; i < tickets[msg.sender].length; i++){
            if(claimJackpot(i)) break;
        }
    }
    
    function claimJackpot(uint purchaseIndex) public returns(bool){
        require(jackpot, "Jackpot not hit");
        TicketIndex memory ticketIndex = tickets[msg.sender][purchaseIndex];
        if(ticketIndex.start <= jackpotLot && ticketIndex.end > jackpotLot){
            depositToken.transfer(msg.sender, depositToken.balanceOf(address(this)));
            return true;
        }
        return false;
    }
}
