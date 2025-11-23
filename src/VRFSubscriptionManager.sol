// SPDX-License-Identifier: MIT
// An example of a consumer contract that also owns and manages the subscription
pragma solidity ^0.8.20;
import {VRFConsumerBaseV2} from "src/VRFConsumerBaseV2.sol";

// End consumer library.
library VRFV2PlusClient {
  // extraArgs will evolve to support new features
  bytes4 public constant EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1"));
  struct ExtraArgsV1 {
    bool nativePayment;
  }

  struct RandomWordsRequest {
    bytes32 keyHash;
    uint256 subId;
    uint16 requestConfirmations;
    uint32 callbackGasLimit;
    uint32 numWords;
    bytes extraArgs;
  }

  function _argsToBytes(ExtraArgsV1 memory extraArgs) internal pure returns (bytes memory bts) {
    return abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs);
  }
}

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here:
 * https://docs.chain.link/docs/link-token-contracts/
 */

abstract contract VRFSubscriptionManager is VRFConsumerBaseV2 {

  // The gas lane to use, which specifies the maximum gas price to bump to.
  // For a list of available gas lanes on each network,
  // see https://docs.chain.link/docs/vrf/v2-5/subscription-supported-networks#configurations
  bytes32 public constant KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

  // Min safe value is 3 
  uint16 public constant REQUEST_CONFIRMATIONS = 6;

  // We only need one source of randomness
  // For multiple drawings, pseudo-RNG can be used since seed is verifiably random
  uint32 public constant NUM_WORDS = 1;

  // A reasonable default is 100000, but this value could be different
  // on other networks.
  uint32 public callbackGasLimit = 500_000;

  // Storage parameters
  uint256 public subscriptionId;

  address public owner;

  modifier onlyOwner() {
    require(msg.sender == owner, "ONLY OWNER");
    _;
  }

  constructor(address _vrfCoordinator, address _owner) VRFConsumerBaseV2(_vrfCoordinator) {
    //Create a new subscription when you deploy the contract.
    owner = _owner;
  }

  // Assumes the subscription is funded sufficiently.
  function requestRandomWords() internal returns(uint) {
    // Will revert if subscription is not set and funded.
    return vrfCoordinator.requestRandomWords(
      VRFV2PlusClient.RandomWordsRequest({
        keyHash: KEY_HASH,
        subId: subscriptionId,
        requestConfirmations: REQUEST_CONFIRMATIONS,
        callbackGasLimit: callbackGasLimit,
        numWords: NUM_WORDS,
        extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
      })
    );
  }

  // Create a new subscription when the contract is initially deployed.
  function _createNewSubscription() internal {
    subscriptionId = vrfCoordinator.createSubscription();
    // Add this contract as a consumer of its own subscription.
    vrfCoordinator.addConsumer(subscriptionId, address(this));
  }

  function topUpSubscription() external payable {
    require(subscriptionId != 0, "No active subscription");
    (bool success,) = payable(address(vrfCoordinator)).call{value: msg.value}(abi.encode(subscriptionId));
    require(success, "Top up failed");
  }

  function cancelSubscription() internal {
    // Cancel the subscription and send the remaining LINK to a wallet address.
    vrfCoordinator.removeConsumer(subscriptionId, address(this));
    vrfCoordinator.cancelSubscription(subscriptionId, owner);
    subscriptionId = 0;
  }

  function setCallbackGasLimit(uint32 newGasLimit) external onlyOwner {
    callbackGasLimit = newGasLimit;
  }
}

