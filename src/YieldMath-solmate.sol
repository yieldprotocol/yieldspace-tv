// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;
/*
   __     ___      _     _
   \ \   / (_)    | |   | | ██╗   ██╗██╗███████╗██╗     ██████╗ ███╗   ███╗ █████╗ ████████╗██╗  ██╗
    \ \_/ / _  ___| | __| | ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗████╗ ████║██╔══██╗╚══██╔══╝██║  ██║
     \   / | |/ _ \ |/ _` |  ╚████╔╝ ██║█████╗  ██║     ██║  ██║██╔████╔██║███████║   ██║   ███████║
      | |  | |  __/ | (_| |   ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║██║╚██╔╝██║██╔══██║   ██║   ██╔══██║
      |_|  |_|\___|_|\__,_|    ██║   ██║███████╗███████╗██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║
       yieldprotocol.com       ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
*/

import {Cast} from "@yield-protocol/utils-v2/src/utils/Cast.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// Ethereum smart contract library implementing Yield Math model with yield bearing tokens.
library YieldMath2 {
    using Cast for uint256;
    using Cast for uint128;
    using FixedPointMathLib for uint256;

    uint128 public constant WAD = 1e18;
    uint128 public constant ONE_FP18 = 1e18;
    uint256 public constant MAX = type(uint128).max; //     Used for overflow checks

    function fyTokenForSharesIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesIn,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {

    }

    function sharesOutForFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {

    }

    function fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesOut,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {

    }
    
    function sharesInForFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenOut,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {

    }
    
    function maxFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128 fyTokenIn) {

    }

    function maxFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128 fyTokenOut) {

    }

    function maxSharesIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128 sharesIn) {

    }

    function invariant(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint256 totalSupply,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public view returns (uint128 result) {

    }


    function _computeA(
        uint128 timeTillMaturity,
        uint256 k,
        uint256 g
    ) public pure returns (uint256) {
        // t = k * timeTillMaturity
        uint256 t = k * timeTillMaturity;
        require(t >= 0, "YieldMath: t must be positive");

        // a = (1 - gt)
        uint256 a = ONE_FP18 - g.mulWadDown(t);
        require(a > 0, "YieldMath: Too far from maturity");

        return a;
    }
}