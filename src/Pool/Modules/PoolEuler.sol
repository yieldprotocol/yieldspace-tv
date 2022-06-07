// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../Pool.sol";
import "../../interfaces/IEToken.sol";

/*

  __     ___      _     _
  \ \   / (_)    | |   | |
   \ \_/ / _  ___| | __| |
    \   / | |/ _ \ |/ _` |
     | |  | |  __/ | (_| |
     |_|  |_|\___|_|\__,_|
       yieldprotocol.com

  ██████╗  ██████╗  ██████╗ ██╗     ███████╗██╗   ██╗██╗     ███████╗██████╗
  ██╔══██╗██╔═══██╗██╔═══██╗██║     ██╔════╝██║   ██║██║     ██╔════╝██╔══██╗
  ██████╔╝██║   ██║██║   ██║██║     █████╗  ██║   ██║██║     █████╗  ██████╔╝
  ██╔═══╝ ██║   ██║██║   ██║██║     ██╔══╝  ██║   ██║██║     ██╔══╝  ██╔══██╗
  ██║     ╚██████╔╝╚██████╔╝███████╗███████╗╚██████╔╝███████╗███████╗██║  ██║
  ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚══════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝

*/

/// Module for using non-4626 compliant Euler etokens as base for the Yield Protocol Pool.sol AMM contract.
/// Adapted from: https://docs.euler.finance/developers/integration-guide
/// @dev Since Euler "eTokens" are not currently ERC4626 compliant, this contract inherits the Yield Pool
/// contract and overwrites the functions that are unique to Yearn Vaults.  For example getBaseCurrentPrice() function
/// calls the convertUnderlyingToBalance() fn. There is also logic to wrap/unwrap (deposit/withdraw) eTokens.
/// @title  PoolEuler.sol
/// @dev Deploy pool with Euler Pool contract and associated fyToken.
/// @author @devtooligan
contract PoolEuler is Pool {
    using MinimalTransferHelper for IERC20Like;

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
    /// @return The price of 1 share of a Euler token in terms of its underlying base asset.
    function _getCurrentSharePrice() internal view virtual override returns (uint256) {
        // The fn takes amount of shares "in accounting units" which means fp18.
        // The return is in the decimals of the underlying.
        return IEToken(address(sharesToken)).convertBalanceToUnderlying(1e18);
    }

    /// Internal function for wrapping base asset tokens.  This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual override returns (uint256 shares) {
        uint256 baseOut = baseToken.balanceOf(address(this));
        if (baseOut == 0) return 0;
        uint256 expectedSharesIn = _wrapPreview(baseOut);

        baseToken.approve(address(sharesToken), baseOut);
        IEToken(address(sharesToken)).deposit(0, baseOut); // first param is subaccount, 0 for primary
        uint256 sharesReceived = _getSharesBalance() - sharesCached;
        require(sharesReceived >= expectedSharesIn, "Not enough shares in"); // TODO: ?? rounding?
        if (receiver != address(this)) {
            sharesToken.safeTransfer(receiver, sharesReceived);
        }
    }

    /// Internal function to preview how many shares will be received when depositing a given amount of assets.
    /// @param base The amount of base asset tokens to preview the deposit.
    /// @return shares The amount of shares that would be returned from depositing.
    function _wrapPreview(uint256 base) internal view virtual override returns (uint256 shares) {
        // The fn takes amount of shares "in accounting units" which means fp18.
        shares = (base * 10**IEToken(address(sharesToken)).decimals()) / _getCurrentSharePrice();
    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// @dev This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return base The amount of base assets sent to the receiver.
    function _unwrap(address receiver) internal virtual override returns (uint256 base) {
        uint256 surplus = _getSharesBalance() - sharesCached;
        if (surplus == 0) return 0;
        uint256 expectedBaseIn = _unwrapPreview(surplus);

        // convert to base
        IEToken(address(sharesToken)).withdraw(0, expectedBaseIn); // first param is subaccount, 0 for primary
        uint256 baseReceived = baseToken.balanceOf(address(this));
        require(baseReceived >= expectedBaseIn, "Not enough base in"); // TODO: ?? rounding?
        if (receiver != address(this)) {
            baseToken.safeTransfer(receiver, baseReceived);
        }
    }

    /// Internal function to preview how many base tokens will be received when unwrapping a given amount of shares.
    /// @dev This should be overridden by modules.
    /// @param shares The amount of shares to preview a redemption.
    /// @return assets The amount of base asset tokens that would be returned from redeeming.
    function _unwrapPreview(uint256 shares) internal view virtual override returns (uint256 assets) {
        assets = (shares * _getCurrentSharePrice()) / 10**IEToken(address(sharesToken)).decimals();
    }

    /// This is used by the constructor to set the base asset token as immutable.
    function _getBaseAsset(address sharesToken_) internal virtual override returns (IERC20Like) {
        return IERC20Like(address(IEToken(sharesToken_).underlyingAsset()));
    }
}
