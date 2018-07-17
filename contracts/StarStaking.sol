pragma solidity 0.4.23;

import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "./Lockable.sol";
import "./StarStakingInterface.sol";


contract StarStaking is StarStakingInterface, Lockable {
    using SafeMath for uint256;

    uint256 public startTime;
    uint256 public endTime;

    ERC20 public token;

    mapping (address => uint256) public totalStakingPointsFor;
    mapping (address => uint256) public totalStakedFor;

    modifier whenStakingOpen {
        require(now >= startTime);
        require(now <= endTime);

        _;
    }

    modifier whenStakingFinished {
        require(now <= endTime);

        _;
    }

    /**
     * @param _token Token that can be staked.
     */
    constructor(ERC20 _token, uint256 _startTime, uint256 _endTime) public {
        require(address(_token) != 0x0);
        require(_startTime < _endTime);
        require(_startTime > now);

        token = _token;
        startTime = _startTime;
        endTime = _endTime;
    }

    /**
     * @dev Stakes a certain amount of tokens.
     * @param amount Amount of tokens to stake.
     */
    function stake(uint256 amount) public whenStakingOpen {
        stakeFor(msg.sender, amount);
    }

    /**
     * @dev Stakes a certain amount of tokens for another user.
     * @param user Address of the user to stake for.
     * @param amount Amount of tokens to stake.
     */
    function stakeFor(address user, uint256 amount) public onlyWhenUnlocked {
        startStaking(stakesFor[user], amount, false);

        require(token.transferFrom(msg.sender, address(this), amount));

        emit Staked(user, amount, totalStakedFor(user));
    }

    /**
     * @dev Unstakes all tokens.
     */
    function unstake() public {
        require(totalStakedFor[msg.sender] > 0);
        
        totalStakingPointsFor[msg.sender] = 0;
        uint256 totalStake = totalStakedFor[msg.sender];

        require(token.transfer(msg.sender, totalStake));
        totalStakedFor[msg.sender] = 0;

        emit Unstaked(msg.sender, totalStake);
    }

    /**
     * @dev Returns the token address.
     * @return Address of token.
     */
    function token() public view returns (address) {
        return token;
    }

    function startStaking(address user, uint256 amount) internal {
        uint256 addedStakingPoints = (endTime.sub(now)).mul(amount);

        totalStakingPointsFor[user] = totalStakingPointsFor[user].add(addedStakingPoints);
        totalStakedFor[user] = totalStakedFor[user].add(amount);
    }
}
