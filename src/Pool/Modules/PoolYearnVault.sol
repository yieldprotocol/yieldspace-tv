// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../Pool.sol";
import "../../interfaces/IYVToken.sol";

/*

  __     ___      _     _
  \ \   / (_)    | |   | |
   \ \_/ / _  ___| | __| |
    \   / | |/ _ \ |/ _` |
     | |  | |  __/ | (_| |
     |_|  |_|\___|_|\__,_|
       yieldprotocol.com

   ██████╗  ██████╗  ██████╗ ██╗  ██╗   ██╗███████╗ █████╗ ██████╗ ███╗   ██╗██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗
   ██╔══██╗██╔═══██╗██╔═══██╗██║  ╚██╗ ██╔╝██╔════╝██╔══██╗██╔══██╗████╗  ██║██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝
   ██████╔╝██║   ██║██║   ██║██║   ╚████╔╝ █████╗  ███████║██████╔╝██╔██╗ ██║██║   ██║███████║██║   ██║██║     ██║
   ██╔═══╝ ██║   ██║██║   ██║██║    ╚██╔╝  ██╔══╝  ██╔══██║██╔══██╗██║╚██╗██║╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║
   ██║     ╚██████╔╝╚██████╔╝███████╗██║   ███████╗██║  ██║██║  ██║██║ ╚████║ ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║
   ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝.SOL

*/

/// Module for using non-4626 compliant Yearn Vault tokens as base for the Yield Protocol Pool.sol AMM contract.
/// For example, Yearn Vault Dai: https://etherscan.io/address/0xC2cB1040220768554cf699b0d863A3cd4324ce32#readContract
/// @dev Since Yearn Vault tokens are not currently ERC4626 compliant, this contract inherits the Yield Pool
/// contract and overwrites the getBaseCurrentPrice() function to call the pricePerShare() function that the
/// Yearn Vault tokens currently use.  All other functionality of the Yield Pool remains the same.
/// @title  PoolYearnVault.sol
/// @dev Deploy pool with Yearn Vault token and associated fyToken.
/// @author @devtooligan
contract PoolYearnVault is Pool {
    /* CONSTRUCTOR
     *****************************************************************************************************************/

    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) Pool(base_, fyToken_, ts_, g1Fee_) {}

    /// Returns the base token current price.
    /// This function should be overriden by modules.
    /// @return The price of 1 share of a Yearn vault token in terms of its underlying.
    function _getCurrentSharePrice() internal view virtual override returns (uint256) {
        return IYVToken(address(sharesToken)).pricePerShare();
    }

    /// Returns the base token current price.
    /// @dev This fn is called from the constructor and avoids the use of unitialized immutables.
    /// This function should be overriden by modules.
    /// @param sharesToken_ Address of Yearn Vault contract to call pricePerShare
    /// @return The price of 1 share of a tokenized vault token in terms of its underlying.
    function _getCurrentSharePriceConstructor(address sharesToken_) internal view virtual override returns (uint256) {
        return IYVToken(sharesToken_).pricePerShare();
    }

    /// Internal function for wrapping underlying asset tokens.  This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual override returns (uint256 shares) {
        shares = IYVToken(address(sharesToken)).deposit(baseToken.balanceOf(address(this)), receiver);
    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// @dev This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return assets The amount of underlying asset assets sent to the receiver.
    function _unwrap(address receiver) internal virtual override returns (uint256 assets) {
        uint256 surplus = _getSharesBalance() - sharesCached;
        assets = IYVToken(address(sharesToken)).withdraw(surplus, receiver);
    }

    /// This is used by the constructor to set the base's underlying asset as immutable.
    function _getBaseUnderlyingAsset(address sharesToken_) internal virtual override returns (IERC20Like) {
        return IERC20Like(address(IYVToken(sharesToken_).token()));
    }

}
