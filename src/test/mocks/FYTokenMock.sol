// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./YVTokenMock.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";



contract FYTokenMock is ERC20Permit, Mintable {
    YVTokenMock public yearnVault;
    uint32 public maturity;

    constructor (
        string memory name_,
        string memory symbol_,
        address yearnVault_,
        uint32 maturity_
    )
        ERC20Permit(
            name_, // should this be generated based on YVToken metadata?
            symbol_, // should this be generated based on YVToken metadata?
            IERC20Metadata(yearnVault_).decimals()
    ) {
        yearnVault = YVTokenMock(yearnVault_);
        maturity = maturity_;
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function redeem(address from, address to, uint256 amount) public {
        _burn(from, amount);
        yearnVault.mint(to, amount);
    }
}
