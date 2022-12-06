pragma solidity ^0.5.16;

contract SponsorWhitelistControl {
  function getSponsorForGas(address contractAddr) public view returns (address) {}
  function getSponsoredBalanceForGas(address contractAddr) public view returns (uint) {}
  function getSponsoredGasFeeUpperBound(address contractAddr) public view returns (uint) {}
  function getSponsorForCollateral(address contractAddr) public view returns (address) {}
  function getSponsoredBalanceForCollateral(address contractAddr) public view returns (uint) {}
  function isWhitelisted(address contractAddr, address user) public view returns (bool) {}
  function isAllWhitelisted(address contractAddr) public view returns (bool) {}
  function addPrivilegeByAdmin(address contractAddr, address[] memory addresses) public {}
  function removePrivilegeByAdmin(address contractAddr, address[] memory addresses) public {}
  function setSponsorForGas(address contractAddr, uint upperBound) public payable {}
  function setSponsorForCollateral(address contractAddr) public payable {}
  function addPrivilege(address[] memory) public {}
  function removePrivilege(address[] memory) public {}
}
