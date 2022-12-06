pragma solidity ^0.5.11;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";

contract Token777Temp
{
    using SafeMath for uint256;
    using Address for address;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    mapping (address => uint256) private _balances; //
     // ERC20-allowances
    mapping (address => mapping (address => uint256)) private _allowances;

    IERC1820Registry constant private ERC1820_REGISTRY = IERC1820Registry(address(0x88887eD889e776bCBe2f0f9932EcFaBcDfCd1820));

    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
        0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    event Transfer(address indexed from, address to, uint256 amount);

    constructor(string memory name, string memory symbol)
        public
    {
        _name = name;
        _symbol = symbol;
        _decimals = 18;
        // register interfaces
        ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
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

    function transferFrom(address holder, address recipient, uint256 value) public returns (bool) {
        require(recipient != address(0), "ERC777: transfer to the zero address");
        require(holder != address(0), "ERC777: transfer from the zero address");

        address spender = msg.sender;

        bool success = _transfer(holder, recipient, value);
        _approve(holder, spender, _allowances[holder][spender].sub(value, "ERC777: transfer amount exceeds allowance"));

        _callTokensReceived(spender, holder, recipient, value, "", "", false);

        return success;
    }

    function _approve(address holder, address spender, uint256 value) internal {
        require(holder != address(0), "ERC777: approve from the zero address");
        require(spender != address(0), "ERC777: approve to the zero address");

        _allowances[holder][spender] = value;
    }

    function transfer(address recipient, uint256 value) public returns (bool) {
        bool success = _transfer(msg.sender, recipient, value);
        _callTokensReceived(msg.sender, msg.sender, recipient, value, "", "", false);
        return success;
    }

    function send(address recipient, uint256 value, bytes memory data) public returns (bool) {
        bool success = _transfer(msg.sender, recipient, value);
        _callTokensReceived(msg.sender, msg.sender, recipient, value, data, "", true);
        return success;
    }


    function _transfer(address sender, address recipient, uint256 value) internal returns (bool) {
        require(recipient != address(0), "transfer to the zero address");
        require(value <= _balances[sender], "transfer insufficient funds");

        _balances[sender] = _balances[sender].sub(value);
        _balances[recipient] = _balances[recipient].add(value);

        emit Transfer(sender, recipient, value);
        return true;
    }

    function burn(uint256 value) public {
      _burn(msg.sender, value);
    }

    function _burn(address account, uint256 value) internal {
      require(account != address(0), "burn from the zero address");
      require(value <= _balances[account], "transfer insufficient funds");

      _balances[account] = _balances[account].sub(value);
      _totalSupply = _totalSupply.sub(value);

      emit Transfer(account, address(0), value);
    }

    function _mint(address account, uint256 value) internal {
        require(account != address(0), "mint to the zero address");

        _totalSupply = _totalSupply.add(value);
        _balances[account] = _balances[account].add(value);

        emit Transfer(address(0), account, value);
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
        address implementer = ERC1820_REGISTRY.getInterfaceImplementer(to, TOKENS_RECIPIENT_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
        } else if (requireReceptionAck) {
            require(!to.isContract(), "FC: token recipient contract has no implementer for ERC777TokensRecipient");
        }
    }
}
