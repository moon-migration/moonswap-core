pragma solidity >=0.5.16;

contract Pauseable {
  address private _owner;
  bool private _isPause;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event SetPaused(address indexed from, bool originalPause, bool newPause);

  constructor() internal {
    _owner = msg.sender;

    _isPause = false;
  }

  function getPause() public view returns(bool) {
    return _isPause;
  }

  modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
  }

  modifier whenPaused() {
     require(!_isPause, "Pauseable: MoonSwap paused");
      _;
  }

  function setPause(bool isPause) public onlyOwner {
    emit SetPaused(msg.sender, _isPause, isPause);
    _isPause = isPause;
  }

  function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
  }
}
