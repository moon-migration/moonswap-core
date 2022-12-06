pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import '../SponsorWhitelistControl.sol';
import "../interfaces/ISavingPool.sol";
import "../interfaces/ISimpleScene.sol";
import '../libraries/Math.sol';

/**
 * Stake LP / Token multi tokens
 * Moonswap multi dig tokens
 */
contract ConfluxMultiFarm is Ownable, ISimpleScene {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
  IERC1820Registry private _erc1820 = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);
  // keccak256("ERC777TokensRecipient")
  bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

  struct UserStake {
    address token;
    uint256 amount;
    uint256 balance;
    uint256 rewardDebt;
  }

  // pid => user
  mapping (uint256 => mapping (address => UserStake)) public userStakes;

  struct UserRewardToken{
      address rewardToken;
      uint256 balance;
      uint256 rewardDebt;
  }

  // pid => user => token => UserRewardToken
  mapping(uint256 => mapping(address => mapping(address => UserRewardToken))) public userRewards;

  struct PoolInfo {
    address token;
    uint256 allocPoint;
    uint256 startBlock;
    uint256 endBlock;
    uint256 lastRewardBlock;  //
    uint256 accTokenPerShare; //
  }

  PoolInfo[] public poolInfo;

  struct RewardTokenInfo {
    address rewardToken;
    uint256 lastRewardBlock;  //
    uint256 accTokenPerShare; //
    uint256 tokenSpeed; // product speed per second
    uint256 totalBalance;
    uint256 sumBalance;
  }

  // pid => rewardToken =>
  mapping(uint256 => mapping(address => RewardTokenInfo)) public poolRewardInfos;
  mapping(uint256 => address[]) public poolRewardTokens;
  // Moon
  address public cMoonToken;
  address public savingPoolAddr;

  uint256 public startFarmBlock;
  uint256 public moonTokenSpeed;
  uint256 public totalAllocPoint = 0;
  address public WCFX; // WCFX

  mapping (address => bool) private _accountCheck;
  address[] private _accountList;

  event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint value);
  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(
        address _cMoon,
        address _savingPoolAddr,
        uint256 _moonTokenSpeed,
        uint256 _startFarmBlock,
        address _WCFX
    ) public {
        cMoonToken = _cMoon;
        savingPoolAddr = _savingPoolAddr;
        moonTokenSpeed = _moonTokenSpeed;
        startFarmBlock = _startFarmBlock;
        WCFX = _WCFX;

        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function poolRewardLen(uint256 _pid) public view returns(uint256){
        return poolRewardTokens[_pid].length;
    }

    function add(uint256 _allocPoint, address _token, uint256 _startBlock,
            uint256 _endBlock, bool _withUpdate) public onlyOwner {
        require(_token != address(0), "ConfluxMultiFarm: ZERO_ADDRESS");
        if(_endBlock > 0 && _endBlock <= _startBlock){
           revert("ConfluxMultiFarm: endblock invalid");
        }

        if (_withUpdate) {
            massUpdatePools();
        }
        if(_startBlock < block.number){
            _startBlock = block.number;
        }
        uint256 lastRewardBlock = block.number > startFarmBlock ? block.number : startFarmBlock;
        if(lastRewardBlock < _startBlock){
            lastRewardBlock = _startBlock;
        }
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            token: _token,
            allocPoint: _allocPoint,
            startBlock: _startBlock,
            endBlock: _endBlock,
            lastRewardBlock: lastRewardBlock,
            accTokenPerShare: 0
        }));
    }

    // add RewardToken pool
    function addPoolReward(uint256 _pid, address _rewardToken) public onlyOwner {
        require(_rewardToken != address(0), "ConfluxMultiFarm: ZERO_ADDRESS");
        RewardTokenInfo storage _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
        require(_rewardTokenInfo.rewardToken == address(0), "ConfluxMultiFarm: rewardToken exists");
        _rewardTokenInfo.rewardToken = _rewardToken;

        poolRewardTokens[_pid].push(_rewardToken);
    }

    // inject invest
    function appendPoolReward(uint256 _pid,
            address _rewardToken,
            uint256 _amount,
            uint256 _tokenSpeed) public onlyOwner {
        _updateRewardPool(_pid, _rewardToken);
        RewardTokenInfo storage _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
        require(_rewardTokenInfo.rewardToken != address(0), "ConfluxMultiFarm: rewardToken not exists");
        IERC20(_rewardToken).safeTransferFrom(address(msg.sender), address(this), _amount);
        _rewardTokenInfo.totalBalance = _rewardTokenInfo.totalBalance.add(_amount);
        _rewardTokenInfo.sumBalance = _rewardTokenInfo.sumBalance.add(_amount);
        _rewardTokenInfo.tokenSpeed = _tokenSpeed;
        PoolInfo memory _pool = poolInfo[_pid];
        _rewardTokenInfo.lastRewardBlock = _pool.lastRewardBlock > block.number ? _pool.lastRewardBlock : block.number;
    }

    function appendPoolRewardCfx(uint256 _pid,
            address _rewardToken,
            uint256 _tokenSpeed) public payable onlyOwner{
        require(_rewardToken == WCFX, "ConfluxMultiFarm: no wcfx");
        uint256 _amount = msg.value;
        _updateRewardPool(_pid, _rewardToken);
        RewardTokenInfo storage _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
        require(_rewardTokenInfo.rewardToken != address(0), "ConfluxMultiFarm: rewardToken not exists");
        _rewardTokenInfo.totalBalance = _rewardTokenInfo.totalBalance.add(_amount);
        _rewardTokenInfo.sumBalance = _rewardTokenInfo.sumBalance.add(_amount);
        _rewardTokenInfo.tokenSpeed = _tokenSpeed;
        PoolInfo memory _pool = poolInfo[_pid];
        _rewardTokenInfo.lastRewardBlock = _pool.lastRewardBlock > block.number ? _pool.lastRewardBlock : block.number;
    }

    function setRewardTokenSpeed(uint256 _pid,
                address _rewardToken,
                uint256 _tokenSpeed) public onlyOwner {
        _updateRewardPool(_pid, _rewardToken);
        RewardTokenInfo storage _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
        require(_rewardTokenInfo.rewardToken != address(0), "ConfluxMultiFarm: rewardToken not exists");
        _rewardTokenInfo.tokenSpeed = _tokenSpeed;
    }

    // update endblock
    function setPoolEndBlock(uint256 _pid, uint256 _endBlock) public onlyOwner {
        //
        require(_endBlock > 0 && _endBlock > block.number, "ConfluxMultiFarm: endblock invalid");
        updatePool(_pid);
        address[] memory _tokens = poolRewardTokens[_pid];
        uint256 _range = _tokens.length;
        for(uint256 i = 0; i < _range; i ++){
            _updateRewardPool(_pid, _tokens[i]);
        }

        poolInfo[_pid].endBlock = _endBlock;
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setMoonTokenSpeed(uint256 _moonTokenSpeed) public onlyOwner {
        massUpdatePools();

        moonTokenSpeed = _moonTokenSpeed;
    }

    function pendingRewardTokens(uint256 _pid, address _user) external view returns (address[5] memory, uint256[5] memory) {
        address[] memory _tokens = poolRewardTokens[_pid];
        address[5] memory _rewardTokens;
        uint256[5] memory _pendingTokens;

        uint256 _range = _tokens.length;
        for(uint256 i = 0; i < _range; i ++){
            _rewardTokens[i] = _tokens[i];
            _pendingTokens[i] = pendingRewardToken(_pid, _user, _tokens[i]);
        }

        return (_rewardTokens, _pendingTokens);
    }

    function pendingRewardToken(uint256 _pid, address _user, address _rewardToken) public view returns(uint256){
      PoolInfo memory _pool = poolInfo[_pid];
      UserStake memory _userStake = userStakes[_pid][_user];
      uint256 tokenSupply = IERC20(_pool.token).balanceOf(address(this));
      RewardTokenInfo memory _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
      UserRewardToken memory _userRewardToken = userRewards[_pid][_user][_rewardToken];
      uint256 accTokenPerShare = _rewardTokenInfo.accTokenPerShare;
      if (block.number > _rewardTokenInfo.lastRewardBlock && tokenSupply != 0) {
          uint256 _tokenReward = _getRewardToken(_pool.endBlock, _rewardTokenInfo.lastRewardBlock, _rewardTokenInfo.tokenSpeed);
          if(_tokenReward > _rewardTokenInfo.totalBalance){
              _tokenReward = _rewardTokenInfo.totalBalance;
          }
          accTokenPerShare = accTokenPerShare.add(_tokenReward.mul(1e12).div(tokenSupply));
      }

      return _userRewardToken.balance.add(
          _userStake.amount.mul(accTokenPerShare).div(1e12).sub(_userRewardToken.rewardDebt)
      );
    }

    function pendingMoonToken(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo memory _pool = poolInfo[_pid];
        UserStake memory _userStake = userStakes[_pid][_user];
        uint256 accTokenPerShare = _pool.accTokenPerShare;
        uint256 tokenSupply = IERC20(_pool.token).balanceOf(address(this));
        if (block.number > _pool.lastRewardBlock && tokenSupply != 0) {
            uint256 _moonReward = _getPoolReward(_pool.endBlock, _pool.lastRewardBlock, _pool.allocPoint);
            accTokenPerShare = accTokenPerShare.add(_moonReward.mul(1e12).div(tokenSupply));
        }

        return _userStake.balance.add(
              _userStake.amount.mul(accTokenPerShare).div(1e12).sub(_userStake.rewardDebt)
          );
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updateRewardPool(uint256 _pid) public {
        address[] memory _tokens = poolRewardTokens[_pid];
        uint256 _range = _tokens.length;
        for(uint256 i = 0; i < _range; i ++){
            _updateRewardPool(_pid, _tokens[i]);
        }
    }

    function _updateRewardPool(uint256 _pid, address _rewardToken) internal {
        RewardTokenInfo storage _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
        if(block.number <= _rewardTokenInfo.lastRewardBlock){
            return;
        }
        PoolInfo memory _pool = poolInfo[_pid];
        uint256 tokenSupply = IERC20(_pool.token).balanceOf(address(this));
        if (tokenSupply == 0) {
            _rewardTokenInfo.lastRewardBlock = block.number;
            return;
        }
        if(_pool.endBlock > 0 && _rewardTokenInfo.lastRewardBlock >= _pool.endBlock){
            _rewardTokenInfo.lastRewardBlock = block.number;
            return;
        }

        if(_rewardTokenInfo.tokenSpeed == 0){
            _rewardTokenInfo.lastRewardBlock = block.number;
            return;
        }

        uint256 _tokenReward = _getRewardToken(_pool.endBlock, _rewardTokenInfo.lastRewardBlock, _rewardTokenInfo.tokenSpeed);
        if(_tokenReward > _rewardTokenInfo.totalBalance){
            _tokenReward = _rewardTokenInfo.totalBalance;
        }
        _rewardTokenInfo.totalBalance = _rewardTokenInfo.totalBalance.sub(_tokenReward);
        _rewardTokenInfo.accTokenPerShare = _rewardTokenInfo.accTokenPerShare.add(_tokenReward.mul(1e12).div(tokenSupply));

        if(_pool.endBlock > 0 && _pool.endBlock < block.number){
            _rewardTokenInfo.lastRewardBlock = _pool.endBlock;
        }else{
            _rewardTokenInfo.lastRewardBlock = block.number;
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage _pool = poolInfo[_pid];
        if (block.number <= _pool.lastRewardBlock) {
            return;
        }
        uint256 tokenSupply = IERC20(_pool.token).balanceOf(address(this));
        if (tokenSupply == 0) {
            _pool.lastRewardBlock = block.number;
            return;
        }

        if(_pool.endBlock > 0 && _pool.lastRewardBlock >= _pool.endBlock){
            _pool.lastRewardBlock = block.number;
            return;
        }

        if(totalAllocPoint == 0){
            _pool.lastRewardBlock = block.number;
            return;
        }

        if(moonTokenSpeed == 0){
          _pool.lastRewardBlock = block.number;
          return;
        }

        uint256 tokenReward = _getPoolReward(_pool.endBlock, _pool.lastRewardBlock, _pool.allocPoint);

        _pool.accTokenPerShare = _pool.accTokenPerShare.add(tokenReward.mul(1e12).div(tokenSupply));
        if(_pool.endBlock > 0 && _pool.endBlock < block.number){
            _pool.lastRewardBlock = _pool.endBlock;
        }else{
          _pool.lastRewardBlock = block.number;
        }
    }

    //
    function deposit(uint256 _pid, uint256 _amount, address _user) public {
        if(_user == address(0)){
            _user = address(msg.sender);
        }
        // check
        uint256 _sceneId = ISavingPool(savingPoolAddr).sceneMap(address(this));
        require(_sceneId > 0, "must add secene");
        PoolInfo storage _pool = poolInfo[_pid];
        UserStake storage _userStake = userStakes[_pid][_user];
        updatePool(_pid);
        updateRewardPool(_pid);
        _fetchSavingPoolFarm();
        if (_userStake.amount > 0) {
            uint256 pending = _userStake.amount.mul(_pool.accTokenPerShare).div(1e12).sub(_userStake.rewardDebt);
            pending = _userStake.balance.add(pending);
            _userStake.balance = pending;
        }
        _digRewardTokenDeposit(_pid, _user, _userStake.amount, _amount);
        IERC20(_pool.token).safeTransferFrom(address(msg.sender), address(this), _amount);
        _userStake.token = _pool.token;
        _userStake.amount = _userStake.amount.add(_amount);
        _userStake.rewardDebt = _userStake.amount.mul(_pool.accTokenPerShare).div(1e12);

        // data migration
        if (!_accountCheck[_user]) {
            _accountCheck[_user] = true;
            _accountList.push(_user);
        }

        emit Deposit(_user, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage _pool = poolInfo[_pid];
        UserStake storage _userStake = userStakes[_pid][msg.sender];
        require(_amount > 0, "user amount is zero");
        require(_userStake.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        updateRewardPool(_pid);
        _fetchSavingPoolFarm();
        uint256 pending = _userStake.amount.mul(_pool.accTokenPerShare).div(1e12).sub(_userStake.rewardDebt);
        pending = _userStake.balance.add(pending);
        _userStake.balance = pending;
        _digRewardTokenWithdraw(_pid, msg.sender, _userStake.amount, _amount);
        _userStake.amount = _userStake.amount.sub(_amount);
        _userStake.rewardDebt = _userStake.amount.mul(_pool.accTokenPerShare).div(1e12);
        IERC20(_pool.token).safeTransfer(address(msg.sender), _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage _pool = poolInfo[_pid];
        UserStake storage _userStake = userStakes[_pid][msg.sender];
        uint256 _amount = _userStake.amount;
        require(_amount > 0, "user amount is zero");
        _userStake.amount = 0;
        _userStake.rewardDebt = 0;
        _userStake.balance = 0;

        IERC20(_pool.token).safeTransfer(address(msg.sender), _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    function _digRewardTokenDeposit(uint256 _pid, address _user, uint256 _userStakeAmount, uint256 _amount) internal {
        address[] memory _tokens = poolRewardTokens[_pid];
        uint256 _range = _tokens.length;
        for(uint256 i = 0; i < _range; i ++){
            address _rewardToken = _tokens[i];
            UserRewardToken storage _userRewardToken = userRewards[_pid][_user][_rewardToken];
            RewardTokenInfo memory _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
            uint256 _pending = _userStakeAmount.mul(_rewardTokenInfo.accTokenPerShare).div(1e12).sub(_userRewardToken.rewardDebt);
            uint256 _balance = _userRewardToken.balance.add(_pending);

            _userRewardToken.balance = _balance;
            _userRewardToken.rewardDebt = _userStakeAmount.add(_amount).mul(_rewardTokenInfo.accTokenPerShare).div(1e12);
        }
    }

    function _digRewardTokenWithdraw(uint256 _pid, address _user, uint256 _userStakeAmount, uint256 _amount) internal {
        address[] memory _tokens = poolRewardTokens[_pid];
        uint256 _range = _tokens.length;
        for(uint256 i = 0; i < _range; i ++){
            address _rewardToken = _tokens[i];
            UserRewardToken storage _userRewardToken = userRewards[_pid][_user][_rewardToken];
            RewardTokenInfo memory _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
            uint256 _pending = _userStakeAmount.mul(_rewardTokenInfo.accTokenPerShare).div(1e12).sub(_userRewardToken.rewardDebt);
            uint256 _balance = _userRewardToken.balance.add(_pending);

            _userRewardToken.balance = _balance;
            _userRewardToken.rewardDebt = _userStakeAmount.sub(_amount).mul(_rewardTokenInfo.accTokenPerShare).div(1e12);
        }
    }

    function harvestBatch(uint256 _pid) public {
        address[] memory _tokens = poolRewardTokens[_pid];
        uint256 _range = _tokens.length;
        updatePool(_pid);
        updateRewardPool(_pid);
        _fetchSavingPoolFarm();
        harvestMoon(_pid);
        for(uint256 i = 0; i < _range; i ++){
            harvest(_pid, _tokens[i]);
        }
    }

    function harvestMoon(uint256 _pid) public {
        PoolInfo memory _pool = poolInfo[_pid];
        UserStake storage _userStake = userStakes[_pid][msg.sender];
        uint256 pending = _userStake.amount.mul(_pool.accTokenPerShare).div(1e12).sub(_userStake.rewardDebt);
        pending = _userStake.balance.add(pending);
        _userStake.balance = 0;
        _moonTokenTransfer(msg.sender, pending);
        _userStake.rewardDebt = _userStake.amount.mul(_pool.accTokenPerShare).div(1e12);
    }

    function harvest(uint256 _pid, address _rewardToken) public {
        UserStake memory _userStake = userStakes[_pid][msg.sender];
        UserRewardToken storage _userRewardToken = userRewards[_pid][msg.sender][_rewardToken];
        RewardTokenInfo memory _rewardTokenInfo = poolRewardInfos[_pid][_rewardToken];
        uint256 _pending = _userStake.amount.mul(_rewardTokenInfo.accTokenPerShare).div(1e12).sub(_userRewardToken.rewardDebt);
        uint256 _balance = _userRewardToken.balance.add(_pending);
        if(_rewardToken == WCFX){
          _safeTransferCFX(msg.sender, _balance);
        }else{
          _safeTokenTransfer(_rewardToken, msg.sender, _balance);
        }

        _userRewardToken.balance = 0;
        _userRewardToken.rewardDebt = _userStake.amount.mul(_rewardTokenInfo.accTokenPerShare).div(1e12);
    }

    function moonBalance() external view returns(uint256) {
      return IERC20(cMoonToken).balanceOf(address(this));
    }

    function scenes(uint256 _sceneId) public view returns(SceneInfo memory) {
        return ISimpleScene(savingPoolAddr).scenes(_sceneId);
    }

    function getSceneId() public view returns(uint256) {
        return ISavingPool(savingPoolAddr).sceneMap(address(this));
    }

    function _moonTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = IERC20(cMoonToken).balanceOf(address(this));
        require(_amount <= tokenBal, "ConfluxStar: Balance insufficient");
        IERC20(cMoonToken).transfer(_to, _amount);
    }

    function _safeTokenTransfer(address _token, address _to, uint256 _amount) internal {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        require(_amount <= tokenBal, "ConfluxStar: Balance insufficient");
        IERC20(_token).transfer(_to, _amount);
    }

    function _safeTransferCFX(address to, uint value) internal {
        (bool success,) = to.call.value(value)(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }

    function _getPoolReward(uint256 _poolEndBlock, uint256 _lastRewardBlock, uint256 _poolAllocPoint) internal view returns(uint256) {

        uint256 _maxEndBlock = block.number;
        if(_poolEndBlock > 0 && _maxEndBlock > _poolEndBlock){
          _maxEndBlock = _poolEndBlock;
        }
        if(_poolEndBlock > 0 && _lastRewardBlock > _poolEndBlock){
          _lastRewardBlock = _poolEndBlock;
        }

        uint256 _totalAllocPoint = ISavingPool(savingPoolAddr).farmTotalAllocPoint();
        if(_totalAllocPoint == 0){
            return 0;
        }

        return _maxEndBlock.sub(_lastRewardBlock).div(2).mul(moonTokenSpeed)
          .mul(_poolAllocPoint).div(_totalAllocPoint);
    }

    function _getRewardToken(uint256 _poolEndBlock, uint256 _lastRewardBlock, uint256 _rewardTokenSpeed) internal view returns(uint256) {
        uint256 _maxEndBlock = block.number;
        if(_poolEndBlock > 0 && _maxEndBlock > _poolEndBlock){
          _maxEndBlock = _poolEndBlock;
        }

        if(_poolEndBlock > 0 && _lastRewardBlock > _poolEndBlock){
          _lastRewardBlock = _poolEndBlock;
        }

        return _maxEndBlock.sub(_lastRewardBlock).div(2).mul(_rewardTokenSpeed);
    }

    function _fetchSavingPoolFarm() internal {
        ISavingPool(savingPoolAddr).harvestSelf();
    }

    function setSavingPoolAddr(address _savingPoolAddr) public onlyOwner {
        require(_savingPoolAddr != address(0), "ConfluxMLFarm: ZERO_ADDRESS");
        savingPoolAddr = _savingPoolAddr;
    }

    // custodian deposit
    function tokensReceived(address operator, address from, address to, uint256 amount,
          bytes calldata userData,
          bytes calldata operatorData) external view {
          return;
    }

    //---------------- Data Migration ----------------------
    function accountTotal() public view returns (uint256) {
       return _accountList.length;
    }

    function accountList(uint256 begin) public view returns (address[100] memory) {
        require(begin >= 0 && begin < _accountList.length, "MoonSwap: accountList out of range");
        address[100] memory res;
        uint256 range = Math.min(_accountList.length, begin.add(100));
        for (uint256 i = begin; i < range; i++) {
            res[i-begin] = _accountList[i];
        }
        return res;
    }
}
