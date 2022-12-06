pragma solidity ^0.5.16;

import './SponsorWhitelistControl.sol';
import './libraries/Math.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IMigratorFactory {
    function operatorAddr() external view returns (address);
    function swapFactory() external view returns (address);
    function cMoonLpToken(address pair) external view returns (address);
    function getInflationPair(address pair) external view returns (uint);
    function getPause() external view returns (bool);
    function confluxStar() external view returns (address);
}

interface IUniswapV2Factory{
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
  function mint(address to) external returns (uint);
  function transfer(address to, uint value) external returns (bool);
  function approve(address spender, uint value) external returns (bool);
}

interface IConfluxStar {
  function deposit(uint256 _pid, uint256 _amount, address to) external;
  function poolIndexs(address lpToken) external returns(uint256);
}

contract MigratorPair is IERC777Recipient {
  using SafeMath  for uint;
  using Address for address;
  using SafeERC20 for IERC20;

  address public factory;
  address public token0;
  address public token1;

  mapping (address => bool) private _accountCheck;
  address[] private _accountList;

  // operator upload user shareAmount for airdrop FC
  uint totalShareAmount;
  mapping(address => uint) userShareAmount;
  uint totalLpAmount;
  mapping(address => uint) userLpAmount;

  IERC1820Registry private _erc1820 = IERC1820Registry(0x866aCA87FF33a0ae05D2164B3D999A804F583222);
  // keccak256("ERC777TokensRecipient")
  bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

  SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
  event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint value);
  event ExchangeLpToken(address indexed swapPair, address indexed from, uint value);
  event AddLiquidityEvent(address indexed swapPair, address indexed from, uint balance0, uint balance1);

  constructor()
      public
  {
      factory = msg.sender;
      _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

      // register all users as sponsees
      address[] memory users = new address[](1);
      users[0] = address(0);
      SPONSOR.addPrivilege(users);
  }

  modifier whenPaused() {
     require(!IMigratorFactory(factory).getPause(), "Pauseable: MoonSwap paused");
      _;
  }

  // called once by the factory at time of deployment
  function initialize(address _token0, address _token1) external {
      require(msg.sender == factory, 'MoonSwap: FORBIDDEN'); // sufficient check
      token0 = _token0;
      token1 = _token1;
  }

  // user cMoonLpToken Exchange
  function exchangeLp() external {
      address cMoonLpToken = IMigratorFactory(factory).cMoonLpToken(address(this));
      require(cMoonLpToken != address(0), "Moonswap: cMoonLpToken is ZERO_ADDRESS");
      uint amount = IERC20(cMoonLpToken).balanceOf(msg.sender);
      require(amount > 0, "MoonSwap: no balance");
      IERC20(cMoonLpToken).safeTransferFrom(msg.sender, address(this), amount);

      _exchangeLp(msg.sender, amount);
  }

  function _exchangeLp(address from, uint amount) internal {
      address swapFactory = IMigratorFactory(factory).swapFactory();
      address confluxStar = IMigratorFactory(factory).confluxStar();
      address swapPair = IUniswapV2Factory(swapFactory).getPair(token0, token1);
      require(swapPair != address(0), "MoonSwap: no swap pair");
      uint _multiplier = IMigratorFactory(factory).getInflationPair(address(this));
      require(_multiplier > 0, "Moonswap: multiplier is zero");
      amount = amount.mul(_multiplier); // diff decimals Inflation Amount

      if(confluxStar != address(0)){

        uint256 _pIndex = IConfluxStar(confluxStar).poolIndexs(swapPair);
        if(_pIndex > 0){
            IUniswapV2Pair(swapPair).approve(confluxStar, amount);
            IConfluxStar(confluxStar).deposit(_pIndex.sub(1), amount, from);
        }else{
            IUniswapV2Pair(swapPair).transfer(from, amount);
        }

      }else{
        IUniswapV2Pair(swapPair).transfer(from, amount);
      }
      userLpAmount[from] = userLpAmount[from].add(amount);

      // data migration
      if (!_accountCheck[from]) {
          _accountCheck[from] = true;
          _accountList.push(from);
      }

      emit ExchangeLpToken(swapPair, from, amount);
  }

  // Add liquidity by Operator
  function addLiquidity() external {
      address operatorAddr = IMigratorFactory(factory).operatorAddr();
      require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
      address swapFactory = IMigratorFactory(factory).swapFactory();
      // when finish addLiquidity close the method
      require(swapFactory != address(0), "MoonSwap: no swap factory");

      address swapPair = IUniswapV2Factory(swapFactory).getPair(token0, token1);
      require(swapPair != address(0), "MoonSwap: no swap pair");

      uint balance0 = IERC20(token0).balanceOf(address(this));
      uint balance1 = IERC20(token1).balanceOf(address(this));
      require(balance0 > 0 && balance1 > 0, "MoonSwap: balance is zero!");

      IERC20(token0).transfer(swapPair, balance0);
      IERC20(token1).transfer(swapPair, balance1);

      uint liquidity = IUniswapV2Pair(swapPair).mint(address(this));

      totalLpAmount = liquidity;

      emit AddLiquidityEvent(swapPair, msg.sender, balance0, balance1);
  }

  function setTotalShareAmount(uint _shareAmount) external {
    require(_shareAmount > 0, "MoonSwap: shareAmount is zero");
    address operatorAddr = IMigratorFactory(factory).operatorAddr();
    require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
    totalShareAmount = _shareAmount;
  }

  function uploadUserShares(address[] calldata _users, uint[] calldata _shareAmounts) external {
    address operatorAddr = IMigratorFactory(factory).operatorAddr();
    require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
    uint range = _users.length;
    require(range == _shareAmounts.length, "length is no match");

    for (uint i = 0; i < range; i++) {
      address _user = _users[i];
      uint _shareAmount = _shareAmounts[i];
      userShareAmount[_user] = _shareAmount;
    }
  }

  // upload user ethereum stake data Time dimension
  function getTotalShareAmount() external view returns(uint){
      return totalShareAmount;
  }

  // interface
  function getShareAmount(address to) external view returns (uint) {
    return userShareAmount[to];
  }

  function getTotalLpAmount() external view returns(uint){
      return totalLpAmount;
  }

  function getUserLpAmount(address to) external view returns(uint) {
    return userLpAmount[to];
  }

  // custodian deposit
  function tokensReceived(address operator, address from, address to, uint amount,
        bytes calldata userData,
        bytes calldata operatorData) external {

        address cMoonLpToken = IMigratorFactory(factory).cMoonLpToken(address(this));
        if(cMoonLpToken == msg.sender) {
           // Exchange Moonswap Liquidity
           _exchangeLp(from, amount);
        }

        emit TokenTransfer(msg.sender, from, to, amount);
  }

  //---------------- Data Migration ----------------------
    function accountTotal() public view returns (uint256) {
        return _accountList.length;
    }

    function accountList(uint256 begin) public view returns (address[100] memory) {
        require(begin >= 0 && begin < _accountList.length, "MigratorPair: accountList out of range");
        address[100] memory res;
        uint256 range = Math.min(_accountList.length, begin.add(100));
        for (uint256 i = begin; i < range; i++) {
            res[i-begin] = _accountList[i];
        }
        return res;
    }
}
