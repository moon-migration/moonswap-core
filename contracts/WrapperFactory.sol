pragma solidity >=0.5.16;

import './WrapperToken.sol';
import './SponsorWhitelistControl.sol';
import "./Pauseable.sol";

contract WrapperFactory is Pauseable {
    address public operator;
    // cToken => mToken
    mapping(address => address) public tokens;
    address[] public cTokens;
    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));

    event CreatedMToken(address indexed _cToken, address _mToken);

    constructor()
      Pauseable()
      public {
        operator = msg.sender;

        // register all users as sponsees
        address[] memory users = new address[](1);
        users[0] = address(0);
        SPONSOR.addPrivilege(users);
    }

    function createToken(address _cToken) external returns (address _mToken){
      require(address(0) != _cToken, "Wrapper: token is ZERO_ADDRESS");
      require(msg.sender == operator, "Wrapper: operator is incorrect");

      bytes memory bytecode = type(WrapperToken).creationCode;
      bytes32 salt = keccak256(abi.encodePacked(_cToken));
      assembly {
          _mToken := create2(0, add(bytecode, 32), mload(bytecode), salt)
      }

      WrapperToken(_mToken).initialize(_cToken);
      if(tokens[_cToken] == address(0)){
          cTokens.push(_cToken);
      }

      tokens[_cToken] = _mToken;

      emit CreatedMToken(_cToken, _mToken);
    }

    function addToken(address _cToken, address _mToken) external {
        require(msg.sender == operator, "Wrapper: operator is incorrect");
        require(_cToken != address(0) && _mToken != address(0), "Wrapper: address incorrect");
        if(tokens[_cToken] == address(0)){
            cTokens.push(_cToken);
        }

        tokens[_cToken] = _mToken;
    }

    function tokenLength() external view returns (uint) {
        return cTokens.length;
    }

    function setOperator(address _operator) external {
       require(msg.sender == operator, "Wrapper: operator is incorrect");

       operator = _operator;
    }

    function modifySymbol(address _cToken, string calldata _symbol) external {
      require(msg.sender == operator, "Wrapper: operator is incorrect");
      address _mToken = tokens[_cToken];
      require(_mToken != address(0), "Wrapper: address incorrect");
      WrapperToken(_mToken).modifySymbol(_symbol);
    }
}
