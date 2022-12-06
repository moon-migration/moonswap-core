## Farm Dig Protocal V2

By staking mLpToken in the Farm pool, while obtaining cMoon, you can also mine a variety of tokens sponsored by the project party.

### Admin Create Pool

```
function add(uint256 _allocPoint, address _token, uint256 _startBlock,
            uint256 _endBlock, bool _withUpdate)
```

### Append Reward Token In Pool

support ERC20 and CFX

```
function appendPoolReward(uint256 _pid,
            address _rewardToken,
            uint256 _amount,
            uint256 _tokenSpeed)

function appendPoolRewardCfx(uint256 _pid,
            address _rewardToken,
            uint256 _tokenSpeed) public payable
```

### User Stake LpToken

```
function deposit(uint256 _pid, uint256 _amount, address _user)
```

### Query user Pending Token

- pending Moon Token

```
function pendingMoonToken(uint256 _pid, address _user) external view returns (uint256)
```

- pending other reward tokens

```
function pendingRewardTokens(uint256 _pid, address _user) external view returns (address[5] memory, uint256[5] memory)
```

### harvest

```
function harvestBatch(uint256 _pid) public
```

### withdraw

The user can retrieve the MLPToken at any time

```
function withdraw(uint256 _pid, uint256 _amount) public
```
