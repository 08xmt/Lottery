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
    IERC20 public depositToken;
    IERC4626 public vault;
    mapping(address => TicketIndex[]) public tickets;
    uint public period;
    uint public jackpotChanceBps;
    mapping(uint => uint) public drawRequestId;
    mapping(uint => uint) public lotDrawn;
    bool public jackpot;
    uint public jackpotLot;

    address charity;

    event Purchase(address purchaser, address indexed receiver, uint start, uint end);
    event Draw(uint indexed period, uint indexed lot, bool jackpot);
    event Jackpot(uint lot, uint prize);
    event Donation(uint amount);

    constructor(uint _period, uint _jackpotChanceBps, address _vrfCoordinator, address _vault, address _owner, address _charity) VRFSubscriptionManager(_vrfCoordinator, _owner) {
        period = _period;
        jackpotChanceBps = _jackpotChanceBps;
        depositToken = IERC20(IERC4626(_vault).asset());
        vault = IERC4626(_vault);
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
            emit Jackpot(lot, totalSupply + donations);
        }
        emit Draw(block.timestamp % period, lot, jackpot);
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
            vault.transfer(charity, vault.balanceOf(address(this)));
            return true;
        }
        return false;
    }
}
