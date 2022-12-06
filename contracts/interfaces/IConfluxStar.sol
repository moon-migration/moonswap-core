pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

interface IConfluxStar {
  function deposit(uint256 _pid, uint256 _amount, address to) external;

  function tokenPerSecond() external view returns(uint256);

  function poolIndexs(address lpToken) external returns(uint256);

  function totalAllocPoint() external view returns(uint256);
}
