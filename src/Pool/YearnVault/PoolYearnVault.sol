// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../Pool4626.sol";
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

/// A Yieldspace AMM implementation for pools which provide liquidity and trading of fyTokens vs base tokens.
/// **The base tokens in this implementation are Yearn tokenized vault shares.**
/// For example, Yearn Vault Dai: https://etherscan.io/address/0xC2cB1040220768554cf699b0d863A3cd4324ce32#readContract
/// @dev Since Yearn Vault tokens are not currently ERC4626 compliant, this contract inherits the Yield Pool4626
/// contract and overwrites the getBaseCurrentPrice() function to call the getPricePerFullShare() function that the Yearn
/// Vault tokens currently use.  All other functionality of the Yield Pool4626 remains the same.
/// @title  PoolYearnVault.sol
/// @dev Deploy pool with Yearn Vault token and associated fyToken.
/// @author Orignal work by @alcueca. Adapted by @devtooligan.  Maths and whitepaper by @aniemburg.
contract PoolYearnVault is Pool4626 {
    /* CONSTRUCTOR
     *****************************************************************************************************************/

    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    )
        Pool4626(
            base_,
            fyToken_,
            ts_,
            g1Fee_
        )
    {}

    /// Returns the base token current price.
    /// @return The price of 1 base token in terms of its underlying as fp18 cast as uint256.
    function getBaseCurrentPrice() public view override virtual returns (uint256) {
        return IYVToken(address(base)).getPricePerFullShare();
    }
}
