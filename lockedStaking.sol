// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Staking is ReentrancyGuard, Ownable(msg.sender) {
    using SafeMath for uint256;
    IERC20 public s_stakingToken;
    IERC20 public s_rewardToken;

    uint256 public rewardRate;
    uint256 private totalStakedTokens;
    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;
    uint256 public constant POINTS_PER_TOKEN = 100 ether;

    uint256 public lockDuration;
    uint256 public lockEndTime;
    bool public isLocked;

    struct StakeInfo {
        uint256 amount;
        uint256 lockStartTime;
        bool hasStaked;
    }

    mapping(address => StakeInfo) public userStakeInfo;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;

    event Staked(
        address indexed user,
        uint256 indexed amount,
        uint256 points,
        uint256 lockStartTime
    );
    event Withdrawn(
        address indexed user,
        uint256 indexed amount,
        uint256 points
    );
    event RewardsClaimed(address indexed user, uint256 indexed amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event LockStatusChanged(bool indexed isLocked);
    event LockDurationSet(uint256 duration);

    constructor(address stakingToken, address rewardToken) {
        s_stakingToken = IERC20(stakingToken);
        s_rewardToken = IERC20(rewardToken);
        rewardRate = 1;
        lockDuration = 60 seconds;
        isLocked = true;
        lockEndTime = block.timestamp + lockDuration;
    }

    function calculatePoints(uint256 amount) public pure returns (uint256) {
        return ((amount * 1e18) / POINTS_PER_TOKEN);
    }

    function updateRewardRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Reward rate must be greater than 0");
        uint256 oldRate = rewardRate;
        console.log("Old Reward Rate", rewardRate);

        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        rewardRate = newRate;
        console.log("New Reward Rate", rewardRate);
        emit RewardRateUpdated(oldRate, newRate);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStakedTokens == 0) {
            return rewardPerTokenStored;
        }
        uint256 totalTime = block.timestamp.sub(lastUpdateTime);
        console.log("Total Time", totalTime);

        uint256 totalRewards = rewardRate.mul(totalTime);
        // console.log("Total Rewards", totalRewards);

        return
            rewardPerTokenStored.add(
                totalRewards.mul(1e18).div(totalStakedTokens)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            userStakeInfo[account]
                .amount
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        uint256 currentTime = block.timestamp - lastUpdateTime;
        console.log("Time Staked: ", currentTime);
        lastUpdateTime = block.timestamp;
        console.log("lastUpdateTime", lastUpdateTime);
        uint256 earnedRewards = earned(account);
        rewards[account] = earnedRewards;
        console.log("Rewards: ", earnedRewards);
        userRewardPerTokenPaid[account] = rewardPerTokenStored;
        _;
    }

    modifier checkLockStatus() {
        if (block.timestamp >= lockEndTime && isLocked) {
            isLocked = false;
            emit LockStatusChanged(false);
        }
        _;
    }

    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
        checkLockStatus
    {
        require(amount > 0, "Amount must be greater than zero");

        // Reset staking info for new stake
        userStakeInfo[msg.sender] = StakeInfo({
            amount: amount,
            lockStartTime: block.timestamp,
            hasStaked: true
        });

        totalStakedTokens = totalStakedTokens.add(amount);
        uint256 points = calculatePoints(userStakeInfo[msg.sender].amount);

        // Reset lock status for new stake
        if (!isLocked) {
            isLocked = true;
            lockEndTime = block.timestamp + lockDuration;
            emit LockStatusChanged(true);
        }

        emit Staked(msg.sender, amount, points, block.timestamp);
        bool success = s_stakingToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer Failed");
    }

    function withdrawStakedTokens(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
        checkLockStatus
    {
        require(amount > 0, "Amount must be greater than zero");
        require(
            userStakeInfo[msg.sender].amount >= amount,
            "Staked amount not enough"
        );

        if (isLocked) {
            require(
                block.timestamp >=
                    userStakeInfo[msg.sender].lockStartTime + lockDuration,
                "Tokens are still locked"
            );
        }

        totalStakedTokens = totalStakedTokens.sub(amount);
        userStakeInfo[msg.sender].amount = userStakeInfo[msg.sender].amount.sub(
            amount
        );

        uint256 points = calculatePoints(userStakeInfo[msg.sender].amount);
        emit Withdrawn(msg.sender, amount, points);

        bool success = s_stakingToken.transfer(msg.sender, amount);
        require(success, "Transfer Failed");
    }

    function getReward()
        external
        nonReentrant
        updateReward(msg.sender)
        checkLockStatus
    {
        require(
            !userStakeInfo[msg.sender].hasStaked,
            "Cannot claim rewards during lockDuration!"
        );
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");
        rewards[msg.sender] = 0;
        emit RewardsClaimed(msg.sender, reward);
        bool success = s_rewardToken.transfer(msg.sender, reward);
        require(success, "Transfer Failed");
    }

    // View Functions
    function getCurrentRewardRate() external view returns (uint256) {
        return rewardRate;
    }

    function getCurrentReward() external view returns (uint256) {
        return earned(msg.sender);
    }

    function getPoints() external view returns (uint256) {
        return calculatePoints(userStakeInfo[msg.sender].amount);
    }

    function getCurrentStakedBalance() external view returns (uint256) {
        return userStakeInfo[msg.sender].amount;
    }

    function getTotalStakedTokens() external view returns (uint256) {
        return totalStakedTokens;
    }

    function getRemainingLockTime(address user)
        external
        view
        returns (uint256)
    {
        if (!isLocked || !userStakeInfo[user].hasStaked) {
            return 0;
        }
        uint256 endTime = userStakeInfo[user].lockStartTime + lockDuration;
        if (block.timestamp >= endTime) {
            return 0;
        }
        return endTime - block.timestamp;
    }

    function UserStakingDetails(address user)
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 pendingRewards,
            uint256 userPoints,
            uint256 lockTimeRemaining,
            bool locked
        )
    {
        uint256 remainingTime = 0;
        if (isLocked && userStakeInfo[user].hasStaked) {
            uint256 endTime = userStakeInfo[user].lockStartTime + lockDuration;
            if (block.timestamp < endTime) {
                remainingTime = endTime - block.timestamp;
            }
        }

        return (
            userStakeInfo[user].amount,
            earned(user),
            calculatePoints(userStakeInfo[user].amount),
            remainingTime,
            isLocked
        );
    }
}
