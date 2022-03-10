// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "hardhat/console.sol";

contract StakingPool is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 lastRewardTime; // Last second that Rewards distribution occurs.
        uint256 accRewardTokenPerShare; // Accumulated Rewards per share, times 1e30. See below.
    }
    struct StakingInfo {
        IERC20 stakeToken;
        IERC20 rewardToken;
        uint256 rewardPerTime;
        uint256 startTime;
        uint256 bonusEndTime;
        uint256 totalStaked;
    }

    uint256 poolSize = 0;
    // Info of each pool.
    mapping(uint256 => PoolInfo) public poolInfo;
    // Staking info of each pool
    mapping(uint256 => StakingInfo) public stakingInfo;
    // Info of each user that stakes LP tokens for each pool
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Maximum emission rate for the StakingPool.
    uint256 public constant MAX_REWARD_PER_TIME = 2 ether;

    event Deposit(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    event SkimStakeTokenFees(address indexed user, uint256 amount);
    event SetRewardPerTime(uint256 oldRewardPerTime, uint256 newRewardPerTime);
    event SetBonusEndTime(uint256 oldBonusEndTime, uint256 newBonusEndTime);
    event SetStartTime(uint256 oldStartTime, uint256 newStartTime);

    function addPool(
        IERC20 _stakeToken,
        IERC20 _rewardToken,
        uint256 _rewardPerTime,
        uint256 _startTime,
        uint256 _bonusEndTime,
        uint256 pid
    ) external onlyOwner {
        require(
            _stakeToken != _rewardToken,
            "addPool: does not support same currency pools"
        );
        require(
            _rewardPerTime <= MAX_REWARD_PER_TIME,
            "addPool: rewardPerTime is larger than MAX_REWARD_PER_TIME"
        );
        // staking pool
        PoolInfo memory pool = PoolInfo({
            lpToken: _stakeToken,
            lastRewardTime: _startTime,
            accRewardTokenPerShare: 0
        });
        poolInfo[pid] = pool;

        StakingInfo memory staking = StakingInfo({
            stakeToken: _stakeToken,
            rewardToken: _rewardToken,
            rewardPerTime: _rewardPerTime,
            startTime: _startTime,
            bonusEndTime: _bonusEndTime,
            totalStaked: 0
        });
        stakingInfo[pid] = staking;

        poolSize++;
    }

    function getPoolSize() external view returns (uint256) {
        return poolSize;
    }

    function getUserInfo(address user, uint256 pid)
        external
        view
        returns (UserInfo memory)
    {
        return userInfo[pid][user];
    }

    // Return reward multiplier over the given _from to _to second.
    function getMultiplier(
        uint256 _from,
        uint256 _to,
        uint256 pid
    ) public view returns (uint256) {
        if (_to <= stakingInfo[pid].bonusEndTime) {
            return _to.sub(_from);
        } else if (_from >= stakingInfo[pid].bonusEndTime) {
            return 0;
        } else {
            return stakingInfo[pid].bonusEndTime.sub(_from);
        }
    }

    // View function to see pending Reward on frontend.
    function pendingReward(address _user, uint256 pid)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][_user];
        uint256 accRewardTokenPerShare = pool.accRewardTokenPerShare;
        if (
            block.timestamp > pool.lastRewardTime &&
            stakingInfo[pid].totalStaked != 0
        ) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp,
                pid
            );
            uint256 tokenReward = multiplier.mul(
                stakingInfo[pid].rewardPerTime
            );
            accRewardTokenPerShare = accRewardTokenPerShare.add(
                tokenReward.mul(1e30).div(stakingInfo[pid].totalStaked)
            );
        }
        return
            user.amount.mul(accRewardTokenPerShare).div(1e30).sub(
                user.rewardDebt
            );
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (stakingInfo[pid].totalStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardTime,
            block.timestamp,
            pid
        );
        uint256 tokenReward = multiplier.mul(stakingInfo[pid].rewardPerTime);
        pool.accRewardTokenPerShare = pool.accRewardTokenPerShare.add(
            tokenReward.mul(1e30).div(stakingInfo[pid].totalStaked)
        );
        pool.lastRewardTime = block.timestamp;
    }

    /// Deposit staking token into the contract to earn rewards.
    /// @dev Since this contract needs to be supplied with rewards we are
    ///  sending the balance of the contract if the pending rewards are higher
    /// @param _amount The amount of staking tokens to deposit
    function deposit(uint256 _amount, uint256 pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 finalDepositAmount = 0;
        updatePool(pid);
        if (user.amount > 0) {
            uint256 pending = user
                .amount
                .mul(pool.accRewardTokenPerShare)
                .div(1e30)
                .sub(user.rewardDebt);
            if (pending > 0) {
                uint256 currentRewardBalance = rewardBalance(pid);
                if (currentRewardBalance > 0) {
                    if (pending > currentRewardBalance) {
                        safeTransferReward(
                            msg.sender,
                            currentRewardBalance,
                            pid
                        );
                    } else {
                        safeTransferReward(msg.sender, pending, pid);
                    }
                }
            }
        }
        if (_amount > 0) {
            uint256 preStakeBalance = totalStakeTokenBalance(pid);
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            finalDepositAmount = totalStakeTokenBalance(pid).sub(
                preStakeBalance
            );
            user.amount = user.amount.add(finalDepositAmount);
            stakingInfo[pid].totalStaked = stakingInfo[pid].totalStaked.add(
                finalDepositAmount
            );
        }
        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(
            1e30
        );

        emit Deposit(msg.sender, finalDepositAmount);
    }

    /// Withdraw rewards and/or staked tokens. Pass a 0 amount to withdraw only rewards
    /// @param _amount The amount of staking tokens to withdraw
    function withdraw(uint256 _amount, uint256 pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(pid);
        uint256 pending = user
            .amount
            .mul(pool.accRewardTokenPerShare)
            .div(1e30)
            .sub(user.rewardDebt);
        if (pending > 0) {
            uint256 currentRewardBalance = rewardBalance(pid);
            if (currentRewardBalance > 0) {
                if (pending > currentRewardBalance) {
                    safeTransferReward(msg.sender, currentRewardBalance, pid);
                } else {
                    safeTransferReward(msg.sender, pending, pid);
                }
            }
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
            stakingInfo[pid].totalStaked = stakingInfo[pid].totalStaked.sub(
                _amount
            );
        }

        user.rewardDebt = user.amount.mul(pool.accRewardTokenPerShare).div(
            1e30
        );

        emit Withdraw(msg.sender, _amount);
    }

    /// Obtain the reward balance of this contract
    /// @return wei balace of conract
    function rewardBalance(uint256 pid) public view returns (uint256) {
        return stakingInfo[pid].rewardToken.balanceOf(address(this));
    }

    // Deposit Rewards into contract
    function depositRewards(uint256 _amount, uint256 pid) external {
        require(_amount > 0, "Deposit value must be greater than 0.");

        stakingInfo[pid].rewardToken.safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        emit DepositRewards(_amount);
    }

    /// @param _to address to send reward token to
    /// @param _amount value of reward token to transfer
    function safeTransferReward(
        address _to,
        uint256 _amount,
        uint256 pid
    ) internal {
        stakingInfo[pid].rewardToken.safeTransfer(_to, _amount);
    }

    /* Admin Functions */

    /// @param _rewardPerTime The amount of reward tokens to be given per second
    function setRewardPerTime(uint256 _rewardPerTime, uint256 pid)
        external
        onlyOwner
    {
        require(
            _rewardPerTime <= MAX_REWARD_PER_TIME,
            "setRewardPerTime: rewardPerTime is larger than MAX_REWARD_PER_TIME"
        );
        updatePool(pid);

        uint256 _oldRewardPerTime = stakingInfo[pid].rewardPerTime;

        stakingInfo[pid].rewardPerTime = _rewardPerTime;

        emit SetRewardPerTime(_oldRewardPerTime, _rewardPerTime);
    }

    /// @param  _bonusEndTime The second when rewards will end
    function setBonusEndTime(uint256 _bonusEndTime, uint256 pid)
        external
        onlyOwner
    {
        require(
            _bonusEndTime > stakingInfo[pid].startTime,
            "setBonusEndTime: bonus end time must be greater than start time"
        );

        uint256 _oldBonusEndTime = stakingInfo[pid].bonusEndTime;

        stakingInfo[pid].bonusEndTime = _bonusEndTime;

        emit SetBonusEndTime(_oldBonusEndTime, _bonusEndTime);
    }

    /// @param  _startTime The second when rewards will start
    function setStartTime(uint256 _startTime, uint256 pid) external onlyOwner {
        require(
            _startTime > block.timestamp,
            "setStartTime: cannot set start time in the past"
        );
        require(
            _startTime < stakingInfo[pid].bonusEndTime,
            "setStartTime: start time must be smaller than bonus end time"
        );
        require(
            stakingInfo[pid].startTime > block.timestamp,
            "setStartTime: pool is already started"
        );

        uint256 _oldStartTime = stakingInfo[pid].startTime;

        stakingInfo[pid].startTime = _startTime;
        poolInfo[pid].lastRewardTime = _startTime;

        emit SetStartTime(_oldStartTime, _startTime);
    }

    /// @dev Obtain the stake token fees (if any) earned by reflect token
    function getStakeTokenFeeBalance(uint256 pid)
        public
        view
        returns (uint256)
    {
        return totalStakeTokenBalance(pid).sub(stakingInfo[pid].totalStaked);
    }

    /// @dev Obtain the stake balance of this contract
    /// @return wei balace of contract
    function totalStakeTokenBalance(uint256 pid) public view returns (uint256) {
        // Return BEO20 balance
        console.log("Address: ", address(stakingInfo[pid].stakeToken));
        return stakingInfo[pid].stakeToken.balanceOf(address(this));
    }

    /// @dev Remove excess stake tokens earned by reflect fees
    function skimStakeTokenFees(uint256 pid) external onlyOwner {
        uint256 stakeTokenFeeBalance = getStakeTokenFeeBalance(pid);
        stakingInfo[pid].stakeToken.safeTransfer(
            msg.sender,
            stakeTokenFeeBalance
        );
        emit SkimStakeTokenFees(msg.sender, stakeTokenFeeBalance);
    }

    /* Emergency Functions */

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        StakingInfo storage staking = stakingInfo[pid];
        pool.lpToken.safeTransfer(msg.sender, user.amount);
        staking.totalStaked = staking.totalStaked.sub(user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount, uint256 pid)
        external
        onlyOwner
    {
        require(_amount <= rewardBalance(pid), "not enough rewards");
        // Withdraw rewards
        safeTransferReward(msg.sender, _amount, pid);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    function getBonusEndTime(uint256 pid) external view returns (uint256) {
        return stakingInfo[pid].bonusEndTime;
    }

    function getStartTime(uint256 pid) external view returns (uint256) {
        return stakingInfo[pid].startTime;
    }

    function getRewardEndTime(uint256 pid) external view returns (uint256) {
        return stakingInfo[pid].rewardPerTime;
    }

    function getTotalStaked(uint256 pid) external view returns (uint256) {
        return stakingInfo[pid].totalStaked;
    }

    function getRewardPerTime(uint256 pid) external view returns (uint256) {
        return stakingInfo[pid].rewardPerTime;
    }
}
