// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import {IERC20Metadata} from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";

abstract contract Mintable is ERC20 {
    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}

contract ETokenMock is Mintable {
    IERC20Metadata internal _underlyingAsset;
    uint256 public price;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        address underlyingAsset_
    ) ERC20(name, symbol, decimals) {
        _underlyingAsset = IERC20Metadata(underlyingAsset_);
    }

    /// @notice Convert an eToken balance to an underlying amount, taking into account current exchange rate
    /// @param balance eToken balance, in internal book-keeping units (18 decimals)
    /// @return Amount in underlying units, (same decimals as underlying token)
    function convertBalanceToUnderlying(uint256 balance) public view returns (uint256) {
        return price * balance / (10 ** decimals);
    }

    /// @notice Convert an underlying amount to an eToken balance, taking into account current exchange rate
    /// @param underlyingAmount Amount in underlying units (same decimals as underlying token)
    /// @return eToken balance, in internal book-keeping units (18 decimals)
    function convertUnderlyingToBalance(uint256 underlyingAmount) public view returns (uint256) {
        return underlyingAmount * (10 ** decimals) / price;
    }

    /// @notice Transfer underlying tokens from sender to the Euler pool, and increase account's eTokens.
    /// unused param subAccountId - 0 for primary, 1-255 for a sub-account.
    /// @param amount In underlying units (use max uint256 for full underlying token balance).
    /// subAccountId is the id of optional subaccounts that can be used by the depositor.
    function deposit(uint256, uint256 amount) external {
        _underlyingAsset.transferFrom(msg.sender, address(this), amount);
        uint256 minted = convertUnderlyingToBalance(amount);
        _mint(msg.sender, minted);
    }

    function underlyingAsset() external view returns (address) {
        return address(_underlyingAsset);
    }

    function setPrice(uint256 price_) public {
        price = price_;
    }

    /// @notice Transfer underlying tokens from Euler pool to sender, and decrease account's eTokens
    /// unused param subAccountId - 0 for primary, 1-255 for a sub-account.
    /// @param amount In underlying units (use max uint256 for full pool balance)
    function withdraw(uint256, uint256 amount) external {
        uint256 burned = convertUnderlyingToBalance(amount);
        _burn(msg.sender, burned);
        _underlyingAsset.transfer(msg.sender, amount);
    }
}
