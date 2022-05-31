// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";


contract USDCMock is ERC20Permit {

    constructor(
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol, 6) { }

    function version() public pure override returns(string memory) { return "2"; }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
