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

import "forge-std/console2.sol";
import {Cast} from "@yield-protocol/utils-v2/src/utils/Cast.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// Ethereum smart contract library implementing Yield Math model with yield bearing tokens.
library YieldMathS {
    using Cast for uint256;
    using Cast for uint128;
    using FixedPointMathLib for uint128;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    error CAndMuMustBePositive();

    uint256 public constant WAD = 1e18;
    uint256 public constant ONE_FP18 = 1e18;
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
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public view returns (uint256 result) {
        if (totalSupply == 0) return 0;
        uint256 a = _computeA(timeTillMaturity, k, g);

        result = _invariant(sharesReserves, fyTokenReserves, totalSupply, a, c, mu);
    }

    function _invariant(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint256 totalSupply, // s
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal view returns (uint256 result) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();

            uint256 za = c.divWadDown(mu).mulWadDown(
                uint256(int256(mu.mulWadDown(
                    sharesReserves.divWadDown(WAD)
                )).powWad(int256(a))
            ));

            uint256 ya = uint256(int256(fyTokenReserves.divWadDown(WAD)).powWad(int256(a)));

            // za            
            // new: 1046749_878211857922501622
            // old: 1046749_877120733165336967

            // ya
            // new: 1294107_460482386983274229
            // old: 1294107_459108161770416706

            // numerator
            // new: 2340857_338694244905775851
            // old: 2340857_336228894935753673

            // denominator
            // new:       2_047619047619047619
            // old:       2_047619047619047619

            // topTerm
            // new: 1387066_105608761466741116
            // old: 1386389_322465120886431258

            // new:       1_155888421340634555
            // old:       1_155324435387600738

            uint256 numerator = za + ya;

            uint256 denominator = c.divWadDown(mu) + WAD;

            uint256 topTerm = uint256(
                int256(
                    c.divWadDown(mu).mulWadDown(
                        numerator.divWadDown(denominator)
                    )
                ).powWad(
                    int256(WAD.divWadDown(a))
                )
            );

            result = (topTerm.mulWadDown(WAD) * WAD) / totalSupply;

            console2.log(result);
        }

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