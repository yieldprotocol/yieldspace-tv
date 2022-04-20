// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";


// TODO: delete this module, leaving it in for now to not break tests
contract BaseMock is ERC20Permit("Base", "YVDAI", 18) {
  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}