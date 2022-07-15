// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TToken is ERC20 {
  address public deployer;
  address public minter;

  constructor() ERC20("tToken", "TTK"){
    deployer = msg.sender;
  }

  function setMinter(address _minter) external {
    require(deployer == msg.sender);
    minter = _minter;
  }

  function mint(address _address, uint256 amount) external {
    require(msg.sender == minter);
    _mint(_address, amount);
  }

  function burn(address account, uint256 amount) external {
    require(msg.sender == minter);
    _burn(account, amount);
  }
}
