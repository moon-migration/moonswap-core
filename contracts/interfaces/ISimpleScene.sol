pragma solidity =0.5.16;
pragma experimental ABIEncoderV2;

interface ISimpleScene {

  struct SceneInfo {
    uint256 sceneId; // scene id no repeat
    uint256 allocPoint;       //
    uint256 lastRewardBlock;  //
    uint256 accTokenPerShare; //
    address sceneAddress;
    uint256 rewardDebt;
  }

  function scenes(uint256 _sceneId) external view returns(SceneInfo memory);
}
