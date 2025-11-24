## Charity Lottery
Simple smart contract for hosting a lottery that deposits an asset into an ERC-4626 vault, 
giving the yield to a charity address and the funds to the lottery winner.
The lottery is a perpetual lottery that can draw lots every *period* of time with each drawing having a fixed chance of drawing a jackpot lot.
The lottery is provably fair, using the chainlink VRF Oracle for random number generation and has further logic to make sure that any lot number has an equal chance of being drawn.
