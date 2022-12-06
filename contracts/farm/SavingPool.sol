pragma solidity ^0.5.11;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../SponsorWhitelistControl.sol";
import "../interfaces/IFansToken.sol";
import "../interfaces/IConfluxStar.sol";
import "../interfaces/ISimpleConflux.sol";

/**
 *  SavingPool migration pool
 *  support kepler、double mint、trade mint etc
 */
contract SavingPool is Ownable, ISimpleConflux{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC1820Registry private _erc1820 = IERC1820Registry(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820);
    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
      0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    address public fansToken;
    address public confluxStar;
    address public cMoonToken;
    uint256 public stakePid;
    uint256 public startBlock;

    struct SceneInfo {
      uint256 sceneId; // scene id no repeat
      uint256 allocPoint;       //
      uint256 lastRewardBlock;  //
      uint256 accTokenPerShare; //
      address sceneAddress;
      uint256 rewardDebt;
    }

    mapping(uint256 => SceneInfo) public scenes;
    uint256[] public sceneIds;
    mapping(address => uint256) public sceneMap;

    uint256 public totalAllocPoint = 0;

    constructor(address _fansToken,
                address _confluxStar,
                address _cMoonToken,
                uint256 _startBlock) public {
        fansToken = _fansToken;
        confluxStar = _confluxStar;
        cMoonToken = _cMoonToken;
        startBlock = _startBlock;

        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function stake(uint256 _pid, uint256 _amount) external onlyOwner {
        IFansToken(fansToken).mint(address(this), _amount);
        IERC20(fansToken).safeApprove(confluxStar, _amount);
        IConfluxStar(confluxStar).deposit(_pid, _amount, address(this));
        stakePid = _pid;
    }

    function mintToken(uint256 _amount) external onlyOwner {
        IFansToken(fansToken).mint(address(this), _amount);
    }

    function farmAllocPoint() public view returns(uint256){
      PoolInfo memory _poolInfo = poolInfo(stakePid);

      return _poolInfo.allocPoint;
    }

    function poolInfo(uint256 _pid) public view returns(PoolInfo memory) {
        return ISimpleConflux(confluxStar).poolInfo(_pid);
    }

    function harvest() public {
        IConfluxStar(confluxStar).deposit(stakePid, 0, address(this));
    }

    function setConfluxStar(address _addr) external onlyOwner {
        require(confluxStar != _addr && _addr != address(0), "SavingPool: addr invalid");
        confluxStar = _addr;
    }

    function addScene(uint256 _sceneId, uint256 _allocPoint, address _sceneAddress) external onlyOwner{
        require(_sceneAddress != address(0), "SavingPool: zero address");
        require(stakePid > 0, "SavingPool: no farm pool create");
        massUpdateScenes();
        SceneInfo storage _scene = scenes[_sceneId];
        require(_sceneId > 0 && _scene.sceneId == 0, "SavingPool: sceneId exists");
        _scene.sceneId = _sceneId;
        _scene.allocPoint = _allocPoint;
        _scene.sceneAddress = _sceneAddress;
        _scene.lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        // Farm
        require(farmAllocPoint() >= totalAllocPoint, "SavingPool: allocPoint over Farm");

        sceneIds.push(_sceneId);

        sceneMap[_sceneAddress] = _sceneId;
    }

    function updateSceneAllocPoint(uint256 _sceneId, uint256 _allocPoint) external onlyOwner {
        massUpdateScenes();
        SceneInfo storage _scene = scenes[_sceneId];
        require(_scene.sceneId > 0, "SavingPool: sceneId no exists");
        totalAllocPoint = totalAllocPoint.sub(_scene.allocPoint).add(_allocPoint);
        require(farmAllocPoint() >= totalAllocPoint, "SavingPool: allocPoint over Farm");
        _scene.allocPoint = _allocPoint;
    }

    function updateSceneAddress(uint256 _sceneId, address _sceneAddress) external onlyOwner {
        require(_sceneAddress != address(0), "SavingPool: zero address");
        massUpdateScenes();
        SceneInfo storage _scene = scenes[_sceneId];
        require(_scene.sceneId > 0, "SavingPool: sceneId no exists");
        _scene.sceneAddress = _sceneAddress;

        sceneMap[_sceneAddress] = _sceneId;
    }

    function harvestScene(uint256 _sceneId) public returns(uint256){
      harvest();
      // from farm to scene
      updateScene(_sceneId);
      SceneInfo storage _scene = scenes[_sceneId];
      require(_scene.sceneAddress != address(0), "SavingPool: zero address");
      uint256 pending = _scene.accTokenPerShare.div(1e12).sub(_scene.rewardDebt);
      _safeTokenTransfer(_scene.sceneAddress, pending);
      _scene.rewardDebt = _scene.accTokenPerShare.div(1e12);

      return pending;
    }

    function harvestSelf() public returns(uint256){
      uint256 _sceneId = sceneMap[msg.sender];
      require(_sceneId > 0, "SavingPool: invalid sceneId");

      return harvestScene(_sceneId);
    }

    function massUpdateScenes() public {
      uint256 _range = sceneIds.length;
      for(uint256 i = 0; i < _range; ++i){
          updateScene(sceneIds[i]);
      }
    }

    function sceneLen() public view returns(uint256) {
        return sceneIds.length;
    }

    function updateScene(uint256 _sceneId) public {
        SceneInfo storage _scene = scenes[_sceneId];
        if(block.number <= _scene.lastRewardBlock){
            return;
        }
        if(totalAllocPoint == 0){
            _scene.lastRewardBlock = block.number;
            return;
        }

        uint256 lpSupply = 1;
        uint256 tokenReward = _getSceneReward(_scene.lastRewardBlock, _scene.allocPoint);

        _scene.accTokenPerShare = _scene.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        _scene.lastRewardBlock = block.number;
    }

    function farmTotalAllocPoint() public view returns(uint256){
        return IConfluxStar(confluxStar).totalAllocPoint();
    }

    function _getSceneReward(uint256 _lastRewardBlock, uint256 _sceneAllocPoint) internal view returns(uint256) {
        uint256 _tokenPerSecond = IConfluxStar(confluxStar).tokenPerSecond();
        uint256 _totalAllocPoint = IConfluxStar(confluxStar).totalAllocPoint();
        if(_totalAllocPoint == 0){
            return 0;
        }

        return block.number.sub(_lastRewardBlock).div(2).mul(_tokenPerSecond)
          .mul(_sceneAllocPoint).div(_totalAllocPoint);
    }

    function _safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = IERC20(cMoonToken).balanceOf(address(this));
        require(_amount <= tokenBal, "ConfluxStar: Balance insufficient");
        IERC20(cMoonToken).transfer(_to, _amount);
    }

    // erc777 receiveToken
    function tokensReceived(address operator, address from, address to, uint amount,
          bytes calldata userData,
          bytes calldata operatorData) external view {
          return;
    }
}
