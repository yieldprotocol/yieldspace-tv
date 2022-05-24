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
    /// @return By always returning 1, we can use this module with any non-tokenized vault base such as DAI.
    function _getBaseCurrentPrice() internal view override virtual returns (uint256) {
        return uint256(10**base.decimals());
    }
}
