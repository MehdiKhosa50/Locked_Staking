// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract LockedStaking is ReentrancyGuard, Ownable(msg.sender) {
    using SafeMath for uint256;

    IERC20 public s_stakingToken;
    IERC20 public s_rewardToken;

    uint256 public rewardMultiplier = 2;
    uint256 public constant POINTS_PER_TOKEN = 100 ether;
    uint256 public lockPeriod;
    uint256 public totalStakedTokens;

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 pendingRewards;
        bool isActive;
    }

    mapping(address => StakeInfo) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 lockEndTime);
    event Withdrawn(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardMultiplierUpdated(uint256 oldRate, uint256 newRate);

    constructor(
        address stakingToken,
        address rewardToken,
        uint256 _lockPeriod
    ) {
        require(_lockPeriod > 0, "Lock period must be greater than 0");
        s_stakingToken = IERC20(stakingToken);
        s_rewardToken = IERC20(rewardToken);
        lockPeriod = _lockPeriod;
    }

    function calculatePoints(uint256 amount) public pure returns (uint256) {
        return (amount * 1e18) / POINTS_PER_TOKEN;
    }

    function calculateRewards(address user) public view returns (uint256) {
        StakeInfo storage stakeInfo = stakes[user];
        if (!stakeInfo.isActive) return 0;

        uint256 currentTime = block.timestamp;
        console.log("current time: ", currentTime);
        uint256 endTime = stakeInfo.endTime;
        console.log("end time: ", endTime);

        uint256 calculatedPoints = calculatePoints(stakeInfo.amount);
        console.log("calculated points: ", calculatedPoints);
        uint256 duration;

        if (currentTime < endTime) {
            duration = currentTime.sub(stakeInfo.startTime);
        } else {
            duration = endTime.sub(stakeInfo.startTime);
        }

        return calculatedPoints.mul(rewardMultiplier).mul(duration);
    }

    function updateRewardMultiplier(uint256 newMultiplier) external onlyOwner {
        require(newMultiplier > 0, "Multiplier must be greater than 0");
        uint256 oldMultiplier = rewardMultiplier;
        rewardMultiplier = newMultiplier;
        console.log("old: ", oldMultiplier);
        console.log("new: ", newMultiplier);
        emit RewardMultiplierUpdated(oldMultiplier, newMultiplier);
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(!stakes[msg.sender].isActive, "Already has active stake");

        uint256 startTime = block.timestamp;
        console.log("start time: ", startTime);
        uint256 endTime = startTime.add(lockPeriod);
        console.log("end time: ", endTime);

        stakes[msg.sender] = StakeInfo({
            amount: amount,
            startTime: startTime,
            endTime: endTime,
            pendingRewards: 0,
            isActive: true
        });

        totalStakedTokens = totalStakedTokens.add(amount);

        emit Staked(msg.sender, amount, endTime);

        bool success = s_stakingToken.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Transfer Failed");
    }

    function withdraw() external nonReentrant {
        StakeInfo storage stakeInfo = stakes[msg.sender];
        require(stakeInfo.isActive, "No active stake found");
        require(
            block.timestamp >= stakeInfo.endTime,
            "Lock period not ended yet"
        );

        uint256 amount = stakeInfo.amount;
        console.log("amount: ", amount);
        uint256 rewards = calculateRewards(msg.sender);
        console.log("rewards: ", rewards);

        totalStakedTokens = totalStakedTokens.sub(amount);
        stakeInfo.isActive = false;
        stakeInfo.amount = 0;
        stakeInfo.pendingRewards = 0;

        emit Withdrawn(msg.sender, amount, rewards);

        bool successStaking = s_stakingToken.transfer(msg.sender, amount);
        require(successStaking, "Staking Token Transfer Failed");

        if (rewards > 0) {
            bool successRewards = s_rewardToken.transfer(msg.sender, rewards);
            require(successRewards, "Reward Token Transfer Failed");
            emit RewardsClaimed(msg.sender, rewards);
        }
    }

    function getStakeInfo(
        address user
    )
        external
        view
        returns (
            uint256 amount,
            uint256 startTime,
            uint256 endTime,
            uint256 pendingRewards,
            bool isActive
        )
    {
        StakeInfo memory stakeInfo = stakes[user];
        return (
            stakeInfo.amount,
            stakeInfo.startTime,
            stakeInfo.endTime,
            calculateRewards(user),
            stakeInfo.isActive
        );
    }

    function getRemainingLockTime(
        address user
    ) external view returns (uint256) {
        StakeInfo memory stakeInfo = stakes[user];
        if (!stakeInfo.isActive) return 0;
        if (block.timestamp >= stakeInfo.endTime) return 0;
        return stakeInfo.endTime.sub(block.timestamp);
    }

    function setLockPeriod(uint256 _lockPeriod) external onlyOwner {
        require(_lockPeriod > 0, "Lock period must be greater than 0");
        console.log("Previous lock period: ", lockPeriod);
        lockPeriod = _lockPeriod;
        console.log("New lock period: ", _lockPeriod);
    }

    function getCurrentRewardMultiplier() external view returns (uint256) {
        return rewardMultiplier;
    }
}