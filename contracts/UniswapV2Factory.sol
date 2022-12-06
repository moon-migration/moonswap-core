pragma solidity >=0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';
import './SponsorWhitelistControl.sol';
import "./Pauseable.sol";

contract UniswapV2Factory is IUniswapV2Factory, Pauseable {
    address public feeTo;
    address public feeToSetter;
    address public migrator; // migratorFactory
    bool public isCreatPair;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
    mapping(address => bool) public tokenBlacklist; // create pair blacklist

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter)
      Pauseable()
      public {
        feeToSetter = _feeToSetter;

        isCreatPair = false;

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);

    }

    modifier canCreatePair() {
          require(isCreatPair || feeToSetter == msg.sender, "MoonSwap: Pause Create Pair");
          _;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external canCreatePair whenPaused returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        require(!tokenBlacklist[tokenA] && !tokenBlacklist[tokenB], "createPair: not allow token");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }

    function setMigrator(address _migrator) external {
        require(msg.sender == feeToSetter, 'MoonSwap: FORBIDDEN');
        migrator = _migrator;
    }

    function setCreatePair(bool _creatPair) external {
      require(msg.sender == feeToSetter, 'MoonSwap: FORBIDDEN');
      isCreatPair = _creatPair;
    }

    function setTokenBlacklist(address tokenAddr, bool _status) external {
      require(msg.sender == feeToSetter, 'Factory: FORBIDDEN');
      tokenBlacklist[tokenAddr] = _status;
    }
}
