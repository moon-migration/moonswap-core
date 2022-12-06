pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

interface ISavingPool {
   function harvestScene(uint256 _sceneId) external returns(uint256);

   function harvestSelf() external returns(uint256);

   function farmTotalAllocPoint() external view returns(uint256);

   function sceneMap(address _addr) external view returns(uint256);
}
