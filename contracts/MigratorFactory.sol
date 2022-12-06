pragma solidity ^0.5.16;

import './SponsorWhitelistControl.sol';
import "@openzeppelin/contracts/utils/Address.sol";
import './MigratorPair.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Pauseable.sol";

// migrator get crosschain address, then listen transfer convert erc777 cToken
// register tokenReceive get the asset

contract MigratorFactory is Pauseable {
    using Address for address;
    using SafeMath  for uint;

    address public operatorAddr;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
    mapping(address => address) public cMoonLpToken;
    address public swapFactory;
    mapping(address => uint) public desiredLiquidity;
    mapping(address => uint) public getInflationPair; // Lp Decimals diff
    address public confluxStar;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _operatorAddr)
      Pauseable()
      public {
        operatorAddr = _operatorAddr;
        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external whenPaused returns (address pair) {
        require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
        require(tokenA != tokenB, 'MoonSwap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'MoonSwap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(MigratorPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        MigratorPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setMoonLpToken(address token0, address token1, address _moonLpToken) external {
        require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
        address pair = getPair[token0][token1];
        require(pair != address(0), "MoonSwap: pair no create");
        cMoonLpToken[pair] = _moonLpToken;
    }

    function setSwapFactory(address _swapFactory) external {
        require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
        swapFactory = _swapFactory;
    }

    function setConfluxStar(address _confluxStar) external {
        require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
        confluxStar = _confluxStar;
    }

    function setOperatorAddr(address _operatorAddr) external {
        require(msg.sender == operatorAddr, 'MoonSwap: FORBIDDEN');
        operatorAddr = _operatorAddr;
    }

    function setDesiredLiquidity(address token0, address token1, uint _desiredLiquidity, uint _multiplier) external {
        require(msg.sender == operatorAddr, "MoonSwap: FORBIDDEN");
        address pair = getPair[token0][token1];
        require(pair != address(0), "MoonSwap: pair no create");
        require(_multiplier > 0, "MoonSwap: multiplier must setting");
        desiredLiquidity[pair] = _desiredLiquidity.mul(_multiplier);
        getInflationPair[pair] = _multiplier;
    }

    function getDesiredLiquidity(address token0, address token1) public view returns(uint){
      address pair = getPair[token0][token1];
      require(pair != address(0), "MoonSwap: pair no create");

      return desiredLiquidity[pair];
    }
}
