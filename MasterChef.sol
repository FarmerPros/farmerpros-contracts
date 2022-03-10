// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./FarmToken.sol";

// MasterChef is the master of Tomato. He can make Tomato and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once TMT is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        //
        // We do some fancy math here. Basically, any point in time, the amount of TMTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTomatoPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTomatoPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. COINs to distribute per second.
        uint256 lastRewardTime; // Last time COINs distribution occurs.
        uint256 accOnionPerShare; // Accumulated COINs per share, times 1e18. See below.
        uint16 depositFeeBP; // Deposit fee in basis points.
        uint16 withdrawFeeBP; // Withdraw fee in basis points.
        uint256 harvestInterval; // Harvest interval in seconds.
        bool hybridHarvest; // Hybrid Harvest feature status (true: active, false: disabled).
    }

    // The COIN TOKEN!
    FarmToken public immutable farmToken;
    // COIN tokens created per second.
    uint256 public coinPerSecond;

    // Dev address.
    address public devAddress;
    // Deposit Fee address
    address public feeAddress;
    // Initial Owner address, to do things such as:
    address public firstOwnerAddress;
    // Liquidity Locker contract address.
    address public lockAddress;

    // Max token supply: 14444 tokens.
    uint256 private constant MAX_SUPPLY = 14444 ether;
    // Max deposit fee: 4%.
    uint256 public constant MAX_DEPOSIT_FEE = 400;
    // Max harvest interval: 2 days.
    uint256 public constant MAX_HARVEST_INTERVAL = 2 days;
    // Total locked up rewards.
    uint256 public totalLockedUpRewards;

    // COIN-USDT Pair for COIN price fetching.
    address private coinusdt;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The timestamp when COIN mining starts.
    uint256 public startTime;
    // To prevent the function "endNonNativesBoost" to be called more than once.
    bool private nonNativeBoostEnd;

    // Maximum coinPerSecond: 0.007.
    uint256 public constant MAX_EMISSION_RATE = 0.007 ether;
    // Initial coinPerSecond: 0.0035.
    uint256 private constant INITIAL_EMISSION_RATE = 0.0035 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetLockAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetVotesAddresses(
        address indexed user,
        address[3] indexed newAddresses
    );
    event UpdateEmissionRate(address indexed user, uint256 newEmissionRate);
    event SetOnionUsdt(address indexed user, address indexed newOnionUsdt);
    event RewardLockedUp(
        address indexed user,
        uint256 indexed pid,
        uint256 amountLockedUp
    );
    event StartTimeChanged(uint256 oldStartTime, uint256 newStartTime);
    event SetHybridHarvest(address indexed user, bool newHybridHarvest);
    event SetPoolLp(
        address indexed user,
        uint256 indexed pid,
        IERC20 newPoolLp
    );

    constructor(FarmToken _farmToken, address _lockAddress) {
        farmToken = _farmToken;
        devAddress = msg.sender;
        feeAddress = msg.sender;
        lockAddress = _lockAddress;
        startTime = 1637006400;

        coinPerSecond = INITIAL_EMISSION_RATE;
        firstOwnerAddress = msg.sender;
        totalAllocPoint = 0;
        nonNativeBoostEnd = false;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // View function to gather the number of pools.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to gather COIN max supply.
    function maxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    // View function to see if hybrid harvest is active or not.
    function isHybrid(uint256 _pid) external view returns (bool) {
        return poolInfo[_pid].hybridHarvest;
    }

    // View function to fetch block timestamp on frontend.
    function blockTimestamp() external view returns (uint256 time) {
        // to assist with countdowns on site
        time = block.timestamp;
    }

    // This is gonne be done in like 6 hours after farming starts, so better to leave it doable without passing thru timelock
    function endNonNativesBoost() external {
        require(
            msg.sender == firstOwnerAddress,
            "endNonNativeBoost: sender is not the owner"
        );
        require(!nonNativeBoostEnd, "endNonNativeBoost: boost already ended");
        nonNativeBoostEnd = true;
        setAllocPoint(0, 4500);
        setAllocPoint(1, 4500);
        setAllocPoint(2, 4500);
        setAllocPoint(3, 4500);
        setAllocPoint(4, 4500);
        setAllocPoint(5, 4500);
        setAllocPoint(6, 4500);
        setAllocPoint(7, 4500);
        setAllocPoint(8, 4500);
        setAllocPoint(9, 4500);
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function addPool(
        uint256 _allocPoint,
        IERC20 _lpToken,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        uint256 _harvestInterval,
        bool _hybridHarvest,
        bool _withUpdate
    ) public onlyOwner nonDuplicated(_lpToken) {
        require(
            _depositFeeBP <= MAX_DEPOSIT_FEE,
            "addPool: invalid deposit fee basis points"
        );
        require(
            _harvestInterval <= MAX_HARVEST_INTERVAL,
            "addPool: invalid harvest interval"
        );

        _lpToken.balanceOf(address(this));

        poolExistence[_lpToken] = true;

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime
            ? block.timestamp
            : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accOnionPerShare: 0,
                depositFeeBP: _depositFeeBP,
                withdrawFeeBP: _withdrawFeeBP,
                harvestInterval: _harvestInterval,
                hybridHarvest: _hybridHarvest
            })
        );
    }

    // Update startTime by the owner (added this to ensure that dev can delay startTime due to the congestion network). Only used if required.
    function setStartTime(uint256 _newStartTime) external onlyOwner {
        require(
            startTime > block.timestamp,
            "setStartTime: farm already started"
        );
        require(
            _newStartTime > block.timestamp,
            "setStartTime: new start time must be future time"
        );

        uint256 _previousStartTime = startTime;

        startTime = _newStartTime;

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTime = startTime;
        }

        emit StartTimeChanged(_previousStartTime, _newStartTime);
    }

    // Update the given pool's COIN allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        uint16 _withdrawFeeBP,
        uint256 _harvestInterval,
        bool _withUpdate
    ) external onlyOwner {
        require(
            _depositFeeBP <= MAX_DEPOSIT_FEE,
            "set: invalid deposit fee basis points"
        );
        require(
            _harvestInterval <= MAX_HARVEST_INTERVAL,
            "set: invalid harvest interval"
        );

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
    }

    // Return reward multiplier over the given _from to _to timestamp.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        pure
        returns (uint256)
    {
        return _to.sub(_from);
    }

    // View function to see pending COINs on frontend.
    function pendingOnion(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accOnionPerShare = pool.accOnionPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (
            block.timestamp > pool.lastRewardTime &&
            lpSupply != 0 &&
            totalAllocPoint > 0
        ) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 coinReward = multiplier
                .mul(coinPerSecond)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);
            accOnionPerShare = accOnionPerShare.add(
                coinReward.mul(1e18).div(lpSupply)
            );
        }

        uint256 pending = user.amount.mul(accOnionPerShare).div(1e18).sub(
            user.rewardDebt
        );
        return pending.add(user.rewardLockedUp);
    }

    // View function to see if user can harvest Onions's.
    function canHarvest(uint256 _pid, address _user)
        public
        view
        returns (bool)
    {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }

    // View function to see if user harvest until time.
    function getHarvestUntil(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        UserInfo storage user = userInfo[_pid][_user];
        return user.nextHarvestUntil;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardTime,
            block.timestamp
        );
        uint256 coinReward = multiplier
            .mul(coinPerSecond)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        if (farmToken.totalSupply() >= MAX_SUPPLY) {
            coinReward = 0;
        } else if (
            farmToken.totalSupply().add(coinReward.mul(11).div(10)) >=
            MAX_SUPPLY
        ) {
            coinReward = (
                MAX_SUPPLY.sub(farmToken.totalSupply()).mul(10).div(11)
            );
        }

        if (coinReward > 0) {
            farmToken.mint(devAddress, coinReward.div(10));
            farmToken.mint(address(this), coinReward);
            pool.accOnionPerShare = pool.accOnionPerShare.add(
                coinReward.mul(1e18).div(lpSupply)
            );
        }

        pool.lastRewardTime = block.timestamp;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Deposit LP tokens to MasterChef for COIN allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);
        payOrLockupPendingOnion(_pid);

        if (_amount > 0) {
            uint256 _balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            // for token that have transfer tax
            _amount = pool.lpToken.balanceOf(address(this)).sub(_balanceBefore);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }

        user.rewardDebt = user.amount.mul(pool.accOnionPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        payOrLockupPendingOnion(_pid);

        if (_amount > 0) {
            uint256 withdrawFee = 0;
            if (pool.withdrawFeeBP > 0) {
                withdrawFee = _amount.mul(pool.withdrawFeeBP).div(10000);
                uint256 lockFee = withdrawFee.sub(withdrawFee.div(2)); // XXX for the auto-lock of half of withdraw fee feature
                pool.lpToken.safeTransfer(feeAddress, withdrawFee.div(2)); // XXX "div(2)" for the auto-lock of half of withdraw fee feature
                pool.lpToken.safeTransfer(lockAddress, lockFee); // XXX for the auto-lock of half of withdraw fee feature
            }
            pool.lpToken.safeTransfer(msg.sender, _amount.sub(withdrawFee));
            user.amount = user.amount.sub(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accOnionPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function getPoolHarvestInterval(uint256 _pid)
        private
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];

        return block.timestamp.add(pool.harvestInterval);
    }

    // Pay or lockup pending coin.
    function payOrLockupPendingOnion(uint256 _pid) private {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = getPoolHarvestInterval(_pid);
        }
        uint256 pending = user.amount.mul(pool.accOnionPerShare).div(1e18).sub(
            user.rewardDebt
        );
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);
                uint256 rewardsToLockup;
                uint256 rewardsToDistribute;
                if (poolInfo[_pid].hybridHarvest) {
                    rewardsToLockup = totalRewards.div(2);
                    rewardsToDistribute = totalRewards.sub(rewardsToLockup);
                } else {
                    rewardsToLockup = 0;
                    rewardsToDistribute = totalRewards;
                }
                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards
                    .sub(user.rewardLockedUp)
                    .add(rewardsToLockup);
                user.rewardLockedUp = rewardsToLockup;
                user.nextHarvestUntil = getPoolHarvestInterval(_pid);
                // send rewards
                safeOnionTransfer(msg.sender, rewardsToDistribute);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount > 0, "emergencyWithdraw: no amount to withdraw");
        uint256 withdrawFee = 0;
        if (pool.withdrawFeeBP > 0) {
            withdrawFee = user.amount.mul(pool.withdrawFeeBP).div(10000);
            uint256 lockFee = withdrawFee.sub(withdrawFee.div(2)); // XXX for the auto-lock of half of withdraw fee feature
            pool.lpToken.safeTransfer(feeAddress, withdrawFee.div(2)); // XXX "div(2)" for the auto-lock of half of withdraw fee feature
            pool.lpToken.safeTransfer(lockAddress, lockFee); // XXX for the auto-lock of half of withdraw fee feature
        }
        pool.lpToken.safeTransfer(msg.sender, user.amount.sub(withdrawFee));
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
    }

    // Safe coin transfer function, just in case if rounding error causes pool to not have enough COINs.
    function safeOnionTransfer(address _to, uint256 _amount) private {
        uint256 coinBal = farmToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > coinBal) {
            transferSuccess = farmToken.transfer(_to, coinBal);
        } else {
            transferSuccess = farmToken.transfer(_to, _amount);
        }
        require(transferSuccess, "safeOnionTransfer: transfer failed");
    }

    // Update the address where 10% emissions are sent (dev address).
    function setDevAddress(address _devAddress) external onlyOwner {
        require(
            _devAddress != address(0),
            "setDevAddress: setting devAddress to the zero address is forbidden"
        );
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    // Update the address where deposit fees are sent (fee address).
    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(
            _feeAddress != address(0),
            "setFeeAddress: setting feeAddress to the zero address is forbidden"
        );
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setLockAddress(address _lockAddress) external onlyOwner {
        require(
            _lockAddress != address(0),
            "setLockAddress: setting lockAddress to the zero address is forbidden"
        );
        lockAddress = _lockAddress;
        emit SetLockAddress(msg.sender, _lockAddress);
    }

    // Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _coinPerSecond) external onlyOwner {
        require(
            _coinPerSecond <= MAX_EMISSION_RATE,
            "updateEmissionRate: value higher than maximum"
        );
        massUpdatePools();
        coinPerSecond = _coinPerSecond;
        emit UpdateEmissionRate(msg.sender, _coinPerSecond);
    }

    // Turn on/off the hybrid harvest function on every pool.
    // Since this is an experimental feature and we may want to disable it anytime (no harm to users if we do that), it will be doable without waiting for the timelock delay.
    function setHybridHarvest(bool _hybridHarvest) external {
        require(
            msg.sender == firstOwnerAddress,
            "setHybridHarvest: sender is not the owner"
        );
        for (uint256 i = 0; i < poolInfo.length; i++) {
            poolInfo[i].hybridHarvest = _hybridHarvest;
        }
        massUpdatePools();
        emit SetHybridHarvest(msg.sender, _hybridHarvest);
    }

    // Turn on/off the hybrid harvest function on a single pool.
    // Since Hybrid Harvest is an experimental feature and we may want to disable it anytime (no harm to users if we do that), it will be doable without waiting for the timelock delay.
    function setHybridHarvestSingle(uint256 _pid, bool _hybridHarvest)
        external
    {
        require(
            msg.sender == firstOwnerAddress,
            "setHybridHarvest: sender is not the owner"
        );
        poolInfo[_pid].hybridHarvest = _hybridHarvest;
        updatePool(_pid);
    }

    // Change only the allocPoint of a pool without having to put in all the parameters needed for the "set()" function.
    // Since this is something that will be done very often (no harm to users), it will be doable without passing thru the timelock.
    function setAllocPoint(uint256 _pid, uint256 _allocPoint) public {
        require(
            msg.sender == firstOwnerAddress,
            "setAllocPoint: sender is not the owner"
        );
        massUpdatePools();
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }
}
