pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

interface ISimpleConflux {

  struct PoolInfo {
    address token;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accTokenPerShare;
  }

  function poolInfo(uint256 _pid) external view returns(PoolInfo memory);
}
