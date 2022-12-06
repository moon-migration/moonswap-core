pragma solidity >=0.5.16;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ConfluxStar {
    function userInfo(uint, address) external view returns (uint, uint);
}

contract MoonVoterProxy {

    IERC20 public constant votes = IERC20(0x86C90add0b8fBE7e4E110aA0B0F4E9582F898496);
    ConfluxStar public constant master = ConfluxStar(0x8D6ab59F0F3E3dDb5931B079E1081Ed4A638ABB4);
    uint public constant pool = uint(0);

    function decimals() external pure returns (uint8) {
        return uint8(18);
    }

    function name() external pure returns (string memory) {
        return "MOONEVD";
    }

    function symbol() external pure returns (string memory) {
        return "MOON";
    }

    function totalSupply() external view returns (uint) {
        return votes.totalSupply();
    }

    function balanceOf(address _voter) external view returns (uint) {
        (uint _votes,) = master.userInfo(pool, _voter);
        return _votes;
    }

    constructor() public {}
}
