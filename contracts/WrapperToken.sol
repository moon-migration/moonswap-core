pragma solidity =0.5.16;

import './interfaces/IERC20.sol';
import './SponsorWhitelistControl.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IWrapperFactory {
  function getPause() external view returns (bool);
}

// ERC777 Token Standard
contract WrapperToken is IERC777Recipient
{
    using SafeMath for uint256;
    using Address for address;

    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    mapping (address => uint256) private _balances; //
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) private _accountCheck;
    address[] private _accountList;

    address public factory;
    address public cToken;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));
    IERC1820Registry constant private _erc1820 = IERC1820Registry(address(0x866aCA87FF33a0ae05D2164B3D999A804F583222));

    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
        0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor()
        public
    {
        factory = msg.sender;

        // register interfaces
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    modifier whenPaused() {
       require(!IWrapperFactory(factory).getPause(), "Pauseable: Wrapper paused");
        _;
    }

    function isPaused() internal view returns(bool){
        return IWrapperFactory(factory).getPause();
    }

    // called once by the factory at time of deployment
    function initialize(address _cToken) external {
        require(msg.sender == factory, 'Wrapper: FORBIDDEN'); // sufficient check
        cToken = _cToken;
        // wrapper token info
        name = string(abi.encodePacked("MOON_", IERC20(_cToken).symbol()));
        symbol = string(abi.encodePacked("m", IERC20(_cToken).symbol()));
        decimals = IERC20(_cToken).decimals();
    }

    function modifySymbol(string calldata _symbol) external {
      require(msg.sender == factory, 'Wrapper: FORBIDDEN'); // sufficient check
      symbol = _symbol;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function allowance(address holder, address spender) public view returns (uint256) {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 value) public returns (bool) {
        address holder = msg.sender;
        _approve(holder, spender, value);
        return true;
    }

    function transferFrom(address holder, address recipient, uint256 value) public whenPaused returns (bool) {
        require(recipient != address(0), "ERC777: transfer to the zero address");
        require(holder != address(0), "ERC777: transfer from the zero address");

        address spender = msg.sender;

        bool success = _transfer(holder, recipient, value);
        _approve(holder, spender, _allowances[holder][spender].sub(value, "ERC777: transfer amount exceeds allowance"));

        _callTokensReceived(spender, holder, recipient, value, "", "", false);

        return true;
    }

    function _approve(address holder, address spender, uint256 value) internal {
        require(holder != address(0), "ERC777: approve from the zero address");
        require(spender != address(0), "ERC777: approve to the zero address");

        _allowances[holder][spender] = value;
    }

    function transfer(address recipient, uint256 value) public whenPaused returns (bool) {
        bool success = _transfer(msg.sender, recipient, value);
        _callTokensReceived(msg.sender, msg.sender, recipient, value, "", "", false);
        return success;
    }

    function send(address recipient, uint256 value, bytes memory data) public whenPaused returns (bool) {
        bool success = _transfer(msg.sender, recipient, value);
        _callTokensReceived(msg.sender, msg.sender, recipient, value, data, "", true);
        return success;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'WrapperToken: TRANSFER_FAILED');
    }

    function _transfer(address sender, address recipient, uint256 value) internal returns (bool) {
        require(recipient != address(0), "transfer to the zero address");
        require(value <= _balances[sender], "transfer insufficient funds");

        if (!_accountCheck[recipient]) {
            _accountCheck[recipient] = true;
            _accountList.push(recipient);
        }

        _balances[sender] = _balances[sender].sub(value);
        _balances[recipient] = _balances[recipient].add(value);

        emit Transfer(sender, recipient, value);
        return true;
    }

    function _deposit(address _user, uint256 _amount) internal {
        if (!_accountCheck[_user]) {
            _accountCheck[_user] = true;
            _accountList.push(_user);
        }

        _mint(_user, _amount);
    }

    function burn(uint256 _amount) public whenPaused {
        _burn(_amount);

        _safeTransfer(cToken, msg.sender, _amount);
    }

    function _burn(uint256 value) internal {
        require(msg.sender != address(0), "burn from the zero address");
        require(value <= _balances[msg.sender], "transfer insufficient funds");

        _balances[msg.sender] = _balances[msg.sender].sub(value);
        totalSupply = totalSupply.sub(value);

        emit Transfer(msg.sender, address(0), value);
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "mint to the zero address");
        require(!isPaused(), "WrapperToken: pause");

        totalSupply = totalSupply.add(value);
        _balances[account] = _balances[account].add(value);

        emit Transfer(address(0), account, value);
    }

    function _min(uint256 value1, uint256 value2) internal pure returns (uint256) {
        if (value1 > value2) {
            return value2;
        }
        return value1;
    }

    function _max(uint256 value1, uint256 value2) internal pure returns (uint256) {
        if (value1 < value2) {
            return value2;
        }
        return value1;
    }

    function _callTokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    )
        private
    {
        address implementer = _erc1820.getInterfaceImplementer(to, TOKENS_RECIPIENT_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
        }
    }

    // cToken deposit
    function tokensReceived(address operator, address from, address to, uint amount,
          bytes calldata userData,
          bytes calldata operatorData) external {

          require(cToken == msg.sender, "WrapperToken: only receive cToken");
          // swap mToken
          _deposit(from, amount);

          emit TokenTransfer(msg.sender, from, to, amount);
    }

    //---------------- Data Migration ----------------------
    function accountTotal() public view returns (uint256) {
        return _accountList.length;
    }

    function accountList(uint256 begin) public view returns (address[100] memory) {
        require(begin >= 0 && begin < _accountList.length, "accountList out of range");
        address[100] memory res;
        uint256 range = _min(_accountList.length, begin.add(100));
        for (uint256 i = begin; i < range; i++) {
            res[i-begin] = _accountList[i];
        }
        return res;
    }
}
