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

 ██████╗  ██████╗  ██████╗ ██╗     ███╗   ██╗ ██████╗ ███╗   ██╗████████╗██╗   ██╗
 ██╔══██╗██╔═══██╗██╔═══██╗██║     ████╗  ██║██╔═══██╗████╗  ██║╚══██╔══╝██║   ██║
 ██████╔╝██║   ██║██║   ██║██║     ██╔██╗ ██║██║   ██║██╔██╗ ██║   ██║   ██║   ██║
 ██╔═══╝ ██║   ██║██║   ██║██║     ██║╚██╗██║██║   ██║██║╚██╗██║   ██║   ╚██╗ ██╔╝
 ██║     ╚██████╔╝╚██████╔╝███████╗██║ ╚████║╚██████╔╝██║ ╚████║   ██║    ╚████╔╝
 ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═══╝   ╚═╝     ╚═══╝ .SOL
*/

/// Module for using non tokenized vault tokens as base for the Yield Protocol Pool.sol AMM contract.
/// For example ordinary DAI, as opposed to yvDAI or Compound DAI.
/// @title  PoolNonTv.sol
/// @dev Deploy pool with base token and associated fyToken.
/// @author @devtooligan
contract PoolNonTv is Pool {
    /* CONSTRUCTOR
     *****************************************************************************************************************/

    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    )
        Pool(
            base_,
            fyToken_,
            ts_,
            g1Fee_
        )
    {}

    /// Returns the base token current price.
    /// This function should be overriden by modules.
    /// @return By always returning 1, we can use this module with any non-tokenized vault base such as WETH.
    function _getBaseCurrentPrice() internal view override virtual returns (uint256) {
        return uint256(10**IERC20Like(address(base)).decimals());
    }


    /// Returns the base token current price.
    /// @dev This fn is called from the constructor and avoids the use of unitialized immutables.
    /// This function should be overriden by modules.
    /// @return The price of 1 share of a tokenized vault token in terms of its underlying cast as uint256.
    function _getBaseCurrentPriceConstructor(address base_) internal view virtual override returns (uint256) {
        return uint256(10**IERC20Like(address(base_)).decimals());
    }
}
