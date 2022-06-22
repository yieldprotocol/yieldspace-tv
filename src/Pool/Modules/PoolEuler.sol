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
/// contract and overwrites the functions that are unique to Euler.
/// @title  PoolEuler.sol
/// @dev Deploy pool with Euler Pool contract and associated fyToken.
/// @author @devtooligan
contract PoolEuler is Pool {
    using MinimalTransferHelper for IERC20Like;

    constructor(
        address euler_, // The main Euler contract address
        address eToken_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) Pool(eToken_, fyToken_, ts_, g1Fee_) {
        // Approve the main Euler contract to take base from the Pool, used on `deposit`.
        _getBaseAsset(eToken_).approve(euler_, type(uint256).max);
    }

    /// **This function is intentionally empty to overwrite the Pool._approveSharesToken fn.**
    /// This is normally used by Pool.constructor give max approval to sharesToken, but Euler tokens require approval
    /// of the main Euler contract -- not of the individual sharesToken contracts. The required approval is given above
    /// in the constructor.
    function _approveSharesToken(IERC20Like baseToken_, address sharesToken_) internal virtual override {}

    /// This is used by the constructor to set the base asset token as immutable.
    function _getBaseAsset(address sharesToken_) internal virtual override returns (IERC20Like) {
        return IERC20Like(address(IEToken(sharesToken_).underlyingAsset()));
    }

    /// Returns the base token current price.
    /// This function should be overriden by modules.
    /// @dev Euler convertBalanceToUnderlying() takes shares converted to 18 decimals ("accounting units")
    /// @return The price of 1 share of a Euler token in terms of its underlying base asset with base asset decimals.
    function _getCurrentSharePrice() internal view virtual override returns (uint256) {
        // The return is in the decimals of the underlying.
        return IEToken(address(sharesToken)).convertBalanceToUnderlying(1e18);
    }

    /// Internal function for wrapping base asset tokens.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual override returns (uint256 shares) {
        uint256 baseOut = baseToken.balanceOf(address(this));
        if (baseOut == 0) return 0;

        IEToken(address(sharesToken)).deposit(0, baseOut); // first param is subaccount, 0 for primary
        uint256 sharesReceived = _getSharesBalance() - sharesCached;
        if (receiver != address(this)) {
            sharesToken.safeTransfer(receiver, sharesReceived);
        }
    }

    /// Internal function to preview how many shares will be received when depositing a given amount of assets.
    /// @param assets The amount of base asset tokens to preview the deposit.
    /// @return shares The amount of shares that would be returned from depositing.
    function _wrapPreview(uint256 assets) internal view virtual override returns (uint256 shares) {
        shares = IEToken(address(sharesToken)).convertUnderlyingToBalance(assets);
    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return assets The amount of assets sent to the receiver.
    function _unwrap(address receiver) internal virtual override returns (uint256 assets) {
        uint256 surplus = _getSharesBalance() - sharesCached;
        if (surplus == 0) return 0;

        // convert to base
        assets = _unwrapPreview(surplus);
        IEToken(address(sharesToken)).withdraw(0, assets); // first param is subaccount, 0 for primary

        if (receiver != address(this)) {
            baseToken.safeTransfer(receiver, baseToken.balanceOf(address(this)));
        }
    }

    /// Internal function to preview how many base tokens will be received when unwrapping a given amount of shares.
    /// @param shares The amount of shares to preview a redemption.
    /// @dev Euler convertBalanceToUnderlying() takes shares converted to 18 decimals ("accounting units")
    /// @return assets The amount of base asset tokens that would be returned from redeeming.
    function _unwrapPreview(uint256 shares) internal view virtual override returns (uint256 assets) {
        // The return is in the decimals of the underlying but the amount provided must be in fp18 "accounting units".
        assets = IEToken(address(sharesToken)).convertBalanceToUnderlying(shares * scaleFactor);
    }
}
