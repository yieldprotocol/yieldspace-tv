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
    error TMustBePositive();
    error TooFarFromMaturity();
    error Underflow();

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
    ) public pure returns (uint128) {}

    function sharesOutForFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {}

    function fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesOut,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {}

    function sharesInForFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenOut,
        uint128 timeTillMaturity,
        uint128 k,
        uint128 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint128) {}

    function maxFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint256 fyTokenIn) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxFYTokenIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) private pure returns (uint256 fyTokenIn) {
        uint256 normalizedSharesReserves = mu.mulWadDown(uint256(sharesReserves));
        uint256 za = c.divWadDown(mu).mulWadDown(uint256(int256(normalizedSharesReserves).powWad(int256(a))));
        uint256 ya = uint256(int256(int128(fyTokenReserves)).powWad(int256(a)));
        uint256 sum = za + ya;

        fyTokenIn = uint256(int256(sum).powWad(int256(WAD.divWadDown(a)))) - uint256(fyTokenReserves);
    }

    function maxFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint256 fyTokenOut) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxFYTokenOut(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) private pure returns (uint256 fyTokenOut) {
        uint256 za = c.divWadDown(mu).mulWadDown(
            uint256(int256(mu.mulWadDown(sharesReserves.divWadDown(WAD))).powWad(int256(a)))
        );

        uint256 ya = uint256(int256(fyTokenReserves.divWadDown(WAD)).powWad(int256(a)));

        uint256 numerator = za + ya;

        uint256 denominator = c.divWadDown(mu) + WAD;

        uint256 rightTerm = uint256(int256(numerator.divWadDown(denominator)).powWad(int256(WAD.divWadDown(a))));

        if ((fyTokenOut = fyTokenReserves - rightTerm.mulWadDown(WAD)) > MAX) revert Underflow();
        if (fyTokenOut > fyTokenReserves) revert Underflow();
    }

    function maxSharesIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint128 c,
        uint128 mu
    ) public pure returns (uint256 sharesIn) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxSharesIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxSharesIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) private pure returns (uint256 sharesIn) {
        uint256 za = c.divWadDown(mu).mulWadDown(
            uint256(int256(mu.mulWadDown(sharesReserves.divWadDown(WAD))).powWad(int256(a)))
        );

        uint256 ya = uint256(int256(fyTokenReserves.divWadDown(WAD)).powWad(int256(a)));

        uint256 numerator = za + ya;

        uint256 denominator = c.divWadDown(mu) + WAD;

        uint256 leftTerm = WAD.divWadDown(mu).mulWadDown(
            uint256(int256(numerator.divWadDown(denominator)).powWad(int256(WAD.divWadDown(a))))
        );

        if ((sharesIn = leftTerm.mulWadDown(WAD) - sharesReserves) > MAX) revert Underflow();
        if (sharesIn > leftTerm.mulWadDown(WAD)) revert Underflow();
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
    ) public pure returns (uint256 result) {
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
    ) internal pure returns (uint256 result) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();

            uint256 za = c.divWadDown(mu).mulWadDown(
                uint256(int256(mu.mulWadDown(sharesReserves.divWadDown(WAD))).powWad(int256(a)))
            );

            uint256 ya = uint256(int256(fyTokenReserves.divWadDown(WAD)).powWad(int256(a)));

            uint256 numerator = za + ya;

            uint256 denominator = c.divWadDown(mu) + WAD;

            uint256 topTerm = uint256(
                int256(c.divWadDown(mu).mulWadDown(numerator.divWadDown(denominator))).powWad(int256(WAD.divWadDown(a)))
            );

            result = (topTerm.mulWadDown(WAD) * WAD) / totalSupply;
        }
    }

    function _computeA(uint128 timeTillMaturity, uint256 k, uint256 g) public pure returns (uint256) {
        // t = k * timeTillMaturity
        uint256 t = k * timeTillMaturity;
        if (t <= 0) revert TMustBePositive();

        // a = (1 - gt)
        uint256 a = ONE_FP18 - g.mulWadDown(t);
        if (a <= 0) revert TooFarFromMaturity();

        return a;
    }
}
