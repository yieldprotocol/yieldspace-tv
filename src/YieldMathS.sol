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

import "forge-std/Test.sol";
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
    error GreaterThanFYTokenReserves();
    error RateOverflowNSI();
    error RateOverflowNSO();
    error RateOverflowNSR();
    error RateOverflowZA();
    error RateOverflowZXA();
    error RateOverflowZYY();
    error RateUnderflow();
    error RoundingError();
    error SumOverflow();
    error TMustBePositive();
    error TooFarFromMaturity();
    error TooManySharesIn();
    error Underflow();
    error UnderflowYXA();

    uint256 public constant WAD = 1e18;
    uint256 public constant MAX = type(uint128).max; //     Used for overflow checks

    function fyTokenOutForSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesIn,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _fyTokenOutForSharesIn(sharesReserves, fyTokenReserves, sharesIn, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _fyTokenOutForSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesIn,
        uint256 a,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);
        if (normalizedSharesReserves > MAX) revert RateOverflowNSR();

        uint256 za = c.divWadDown(mu).mulWadDown(
            uint256(int256(mu.mulWadDown(normalizedSharesReserves)).powWad(int256(a)))
        );
        if (za > MAX) revert RateOverflowZA();

        uint256 ya = _powHelper(fyTokenReserves, a);

        uint256 normalizedSharesIn = mu.mulWadDown(sharesIn);
        if (normalizedSharesIn > MAX) revert RateOverflowNSI();

        uint256 zx = normalizedSharesReserves + normalizedSharesIn;
        if (zx > MAX) revert TooManySharesIn();

        uint256 zxa = c.divWadDown(mu).mulWadDown(_powHelper(zx, a));
        if (zxa > MAX) revert RateOverflowZXA();

        uint256 sum = za + ya - zxa;
        if (sum > (za + ya)) revert SumOverflow();

        uint256 fyTokenOut = fyTokenReserves - _powHelper(sum, WAD.divWadDown(a));
        if (fyTokenOut > MAX) revert RoundingError();
        if (fyTokenOut > fyTokenReserves) revert GreaterThanFYTokenReserves();

        return fyTokenOut;
    }

    function sharesOutForFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenIn,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _sharesOutForFYTokenIn(sharesReserves, fyTokenReserves, fyTokenIn, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _sharesOutForFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenIn,
        uint256 a,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);
        if (normalizedSharesReserves > MAX) revert RateOverflowNSR();

        uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));

        if (za > MAX) revert RateOverflowZA();

        // za + ya - yxa 
        uint256 zaYaYxa = za + _powHelper(fyTokenReserves, a) - _powHelper(fyTokenReserves + fyTokenIn, a);
        if (zaYaYxa > MAX) revert RateOverflowZYY();

        uint256 rightTerm = (_powHelper(zaYaYxa.divWadDown(c.divWadDown(mu)), WAD.divWadDown(a))).divWadDown(mu);

        if (rightTerm > sharesReserves) revert RateUnderflow();

        return sharesReserves - rightTerm;
    }

    function fyTokenInForSharesOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesOut,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _fyTokenInForSharesOut(sharesReserves, fyTokenReserves, sharesOut, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _fyTokenInForSharesOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesOut,
        uint256 a,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            uint256 sum;
            {
                uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);
                if (normalizedSharesReserves > MAX) revert RateOverflowNSR();

                uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));
                if (za > MAX) revert RateOverflowZA();

                uint256 ya = _powHelper(fyTokenReserves, a);

                uint256 normalizedSharesOut = mu.mulWadDown(sharesOut);
                if (normalizedSharesOut > MAX) revert RateOverflowNSO();

                if (normalizedSharesOut > normalizedSharesReserves) revert TooManySharesIn();
                uint256 zx = normalizedSharesReserves - normalizedSharesOut;

                uint256 zxa = c.divWadDown(mu).mulWadDown(_powHelper(zx, a));

                sum = za + ya - zxa;
                if (sum > MAX) revert GreaterThanFYTokenReserves();
            }

            uint256 result = _powHelper(sum, WAD.divWadDown(a)) - fyTokenReserves;
            if (result > MAX) revert RoundingError();

            return result;
        }
    }

    function sharesInForFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenOut,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        unchecked {
            if(c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _sharesInForFYTokenOut(sharesReserves, fyTokenReserves, fyTokenOut, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _sharesInForFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenOut,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        unchecked {
            if (mu.mulWadDown(sharesReserves) > MAX) revert RateOverflowNSR();
            uint256 za = c.divWadDown(mu).mulWadDown(
                uint256(int256(mu.mulWadDown(sharesReserves.divWadDown(WAD))).powWad(int256(a)))
            );
            if (za > MAX) revert RateOverflowZA();

            uint256 ya = _powHelper(fyTokenReserves, a);

            uint256 yxa = _powHelper(fyTokenReserves - fyTokenOut, a);
            if (fyTokenOut > fyTokenReserves) revert UnderflowYXA();

            uint256 zaYaYxa = (za + ya - yxa);
            if (zaYaYxa > MAX) revert RateOverflowZYY(); 

            uint256 subtotal = WAD.divWadDown(mu).mulWadDown(
                _powHelper(zaYaYxa.divWadDown(c.divWadDown(mu)), WAD.divWadDown(a))
            );
        
            uint256 result = subtotal - sharesReserves;
            if (result > subtotal) revert Underflow();

            return result;
        }
    }

    function maxFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 fyTokenIn) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxFYTokenIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 fyTokenIn) {
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);
        if (normalizedSharesReserves > MAX) revert RateOverflowNSR();
        uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));
        uint256 ya = uint256(int256(fyTokenReserves).powWad(int256(a)));
        uint256 sum = za + ya;
        if (sum > MAX) revert GreaterThanFYTokenReserves();

        fyTokenIn = _powHelper(sum, WAD.divWadDown(a)) - fyTokenReserves;
        if (fyTokenIn > MAX) revert RoundingError();
    }

    function maxFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 fyTokenOut) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxFYTokenOut(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 fyTokenOut) {
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
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 sharesIn) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxSharesIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 sharesIn) {
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
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 totalSupply,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 result) {
        if (totalSupply == 0) return 0;
        uint256 a = _computeA(timeTillMaturity, k, g);

        result = _invariant(sharesReserves, fyTokenReserves, totalSupply, a, c, mu);
    }

    function _invariant(
        uint256 sharesReserves, // z
        uint256 fyTokenReserves, // x
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

    function _computeA(uint256 timeTillMaturity, uint256 k, uint256 g) internal pure returns (uint256) {
        // t = k * timeTillMaturity
        uint256 t = k * timeTillMaturity;
        if (t <= 0) revert TMustBePositive();

        // a = (1 - gt)
        uint256 a = WAD - g.mulWadDown(t);
        if (a <= 0) revert TooFarFromMaturity();

        return a;
    }

    function _powHelper(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        } else {
            result = uint256(int256(x).powWad(int256(y)));
        }
    }

}
