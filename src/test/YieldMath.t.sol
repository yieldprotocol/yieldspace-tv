// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13; /*
  __     ___      _     _
  \ \   / (_)    | |   | | ████████╗███████╗███████╗████████╗███████╗
   \ \_/ / _  ___| | __| | ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    \   / | |/ _ \ |/ _` |    ██║   █████╗  ███████╗   ██║   ███████╗
     | |  | |  __/ | (_| |    ██║   ██╔══╝  ╚════██║   ██║   ╚════██║
     |_|  |_|\___|_|\__,_|    ██║   ███████╗███████║   ██║   ███████║
      yieldprotocol.com       ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚══════╝
*/

import "ds-test/test.sol";

import {Exp64x64} from "./../Exp64x64.sol";
import {YieldMath} from "./../YieldMath.sol";
import {Math64x64} from "./../Math64x64.sol";

import "./helpers.sol";

contract YieldMathTest is DSTest {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    /**TESTS

        Tests grouped by function:
        1. function fyTokenOutForSharesIn
        2. function sharesInForFYTokenOut
        3. function sharesOutForFYTokenIn
        4. function fyTokenInForSharesOut

        Links to Desmos for each formula can be found at:
        https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

        Test name prefixe definitions:
        testUnit_          - Unit tests for common edge cases
        testFail_<reason>_ - Unit tests code reverts appropriately
        testFuzz_          - Property based fuzz tests

    ******************************************************************************************************************/

    uint128 public constant sharesReserves = uint128(1100000 * 1e18); // Z
    uint128 public constant fyTokenReserves = uint128(1500000 * 1e18); // Y
    uint128 public constant timeTillMaturity = uint128(90 * 24 * 60 * 60 * 10); // T

    int128 immutable k;

    uint256 public constant gNumerator = 95;
    uint256 public constant gDenominator = 100;
    int128 public g1; // g to use when selling shares to pool
    int128 public g2; // g to use when selling fyTokens to pool

    uint256 public constant cNumerator = 11;
    uint256 public constant cDenominator = 10;
    int128 public c;

    uint256 public constant muNumerator = 105;
    uint256 public constant muDenominator = 100;
    int128 public mu;

    constructor() {
        uint256 invK = 25 * 365 * 24 * 60 * 60 * 10;
        k = uint256(1).fromUInt().div(invK.fromUInt());

        g1 = gNumerator.fromUInt().div(gDenominator.fromUInt());
        g2 = gDenominator.fromUInt().div(gNumerator.fromUInt());
        c = cNumerator.fromUInt().div(cDenominator.fromUInt());
        mu = muNumerator.fromUInt().div(muDenominator.fromUInt());
    }

    function assertSameOrSlightlyLess(uint128 result, uint128 expectedResult) public pure {
        require((expectedResult - result) <= 1);
    }

    function assertSameOrSlightlyMore(uint128 result, uint128 expectedResult) public pure {
        require((result - expectedResult) <= 1);
    }

    /* 1. function fyTokenOutForSharesIn
     ***************************************************************/

    function testUnit_fyTokenOutForSharesIn__baseCases() public view {
        // should match Desmos for selected inputs
        uint128[6] memory sharesAmounts = [
            uint128(50_000 * 1e18),
            uint128(100_000 * 1e18),
            uint128(200_000 * 1e18),
            uint128(500_000 * 1e18),
            uint128(900_000 * 1e18),
            uint128(1_379_104 * 1e18)
        ];
        uint128[6] memory expectedResults = [
            uint128(55_113),
            uint128(110_185),
            uint128(220_202),
            uint128(549_235),
            uint128(985_292),
            uint128(1_500_000)
        ];
        uint128 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            result =
                YieldMath.fyTokenOutForSharesIn(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g1,
                    c,
                    mu
                ) /
                1e18;

            assertSameOrSlightlyLess(result, expectedResults[idx]);
        }
    }

    function testUnit_fyTokenOutForSharesIn__mirror() public {
        // should match Desmos for selected inputs
        uint128[4] memory sharesAmounts = [
            uint128(50000 * 1e18),
            uint128(100000 * 1e18),
            uint128(200000 * 1e18),
            uint128(830240163000000000000000)
        ];
        uint128 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            emit log_named_uint("sharesAmount", sharesAmounts[idx]);
            emit log_named_uint("sharesReserves", sharesReserves);
            result = YieldMath.fyTokenOutForSharesIn(
                sharesReserves,
                fyTokenReserves,
                sharesAmounts[idx], // x or ΔZ
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            emit log_named_uint("result", result);
            uint128 resultShares = YieldMath.sharesInForFYTokenOut(
                sharesReserves,
                fyTokenReserves,
                result,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            emit log_named_uint("resultShares", resultShares);

            assertSameOrSlightlyLess(resultShares / 1e18, sharesAmounts[idx] / 1e18);
        }
    }

    function testUnit_fyTokenOutForSharesIn__atMaturity() public view {
        //should have a price of one at maturity
        uint128 amount = uint128(100000 * 1e18);
        uint128 result = YieldMath.fyTokenOutForSharesIn(sharesReserves, fyTokenReserves, amount, 0, k, g1, c, mu) /
            1e18;
        uint128 expectedResult = uint128((amount * cNumerator) / cDenominator) / 1e18;

        assertSameOrSlightlyLess(result, expectedResult);
    }

    function testUnit_fyTokenOutForSharesIn__increaseG() public view {
        // increase in g results in increase in fyTokenOut
        // NOTE: potential fuzz test
        uint128 amount = uint128(100000 * 1e18);
        uint128 result1 = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            amount,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;

        int128 bumpedG = uint256(975).fromUInt().div(gDenominator.fromUInt());
        uint128 result2 = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            amount,
            timeTillMaturity,
            k,
            bumpedG,
            c,
            mu
        ) / 1e18;
        require(result2 > result1);
    }

    function testFuzz_fyTokenOutForSharesIn(uint256 passedIn) public {
        uint128 sharesAmount = coerceUInt256To128(passedIn, 1000000000000000000, 949227786000000000000000);
        uint128 result = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        if (result < sharesAmount) {
            emit log_named_uint("sharesAmount", sharesAmount);
            emit log_named_uint("result", result);
        }
        require(result > sharesAmount);
    }

    function testFail_fyTokenOutForSharesIn__overReserves() public view {
        // Per desmos, this would require more fytoken than are available, so it should revert.
        YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            1_380_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;
    }

    /* 2. function sharesInForFYTokenOut
     ***************************************************************/
    function testUnit_sharesInForFYTokenOut__baseCases() public view {
        // should match Desmos for selected inputs
        uint128[5] memory fyTokenAmounts = [
            uint128(50000 * 1e18),
            uint128(100_000 * 1e18),
            uint128(200_000 * 1e18),
            uint128(900_000 * 1e18),
            uint128(1_500_000 * 1e18)
        ];
        uint128[5] memory expectedResults = [
            uint128(45359),
            uint128(90_749),
            uint128(181_625),
            uint128(821_505),
            uint128(1_379_104)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            result =
                YieldMath.sharesInForFYTokenOut(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g1,
                    c,
                    mu
                ) /
                1e18;

            assertSameOrSlightlyMore(result, expectedResults[idx]);
        }
    }

    function testUnit_sharesInForFYTokenOut__mirror() public {
        // should match Desmos for selected inputs
        uint128[4] memory fyTokenAmounts = [
            uint128(50000 * 1e18),
            uint128(100000 * 1e18),
            uint128(200000 * 1e18),
            uint128(830240163000000000000000)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            emit log_named_uint("fyTokenAmount", fyTokenAmounts[idx]);
            emit log_named_uint("fyTokenReserves", fyTokenReserves);
            result = YieldMath.fyTokenOutForSharesIn(
                sharesReserves,
                fyTokenReserves,
                fyTokenAmounts[idx], // x or ΔZ
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            emit log_named_uint("result", result);
            uint128 resultFYTokens = YieldMath.sharesInForFYTokenOut(
                sharesReserves,
                fyTokenReserves,
                result,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            emit log_named_uint("resultFYTokens", resultFYTokens);
            assertSameOrSlightlyMore(resultFYTokens / 1e18, fyTokenAmounts[idx] / 1e18);
        }
    }

    function testFail_sharesInForFYTokenOut__overReserves() public view {
        // Per desmos, this would require more fytoken than are available, so it should revert.
        YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            1_501_000, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;
    }

    /* 3. function sharesOutForFYTokenIn
     ***************************************************************/

    function testUnit_sharesOutForFYTokenIn__baseCases() public view {
        // should match Desmos for selected inputs
        uint128[5] memory fyTokenAmounts = [
            uint128(25000 * 1e18),
            uint128(50_000 * 1e18),
            uint128(100_000 * 1e18),
            uint128(200_000 * 1e18),
            uint128(500_000 * 10**18)
        ];
        uint128[5] memory expectedResults = [
            uint128(22_661),
            uint128(45_313),
            uint128(90_592),
            uint128(181_041),
            uint128(451_473)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            result =
                YieldMath.sharesOutForFYTokenIn(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g2,
                    c,
                    mu
                ) /
                1e18;

            assertSameOrSlightlyMore(result, expectedResults[idx]);
        }
    }

    function testUnit_sharesOutForFYTokenIn__mirror() public view {
        // should match Desmos for selected inputs
        uint128[4] memory fyTokenAmounts = [
            uint128(50000 * 1e18),
            uint128(100000 * 1e18),
            uint128(200000 * 1e18),
            uint128(1_000_000 * 1e18)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            result = YieldMath.fyTokenInForSharesOut(
                sharesReserves,
                fyTokenReserves,
                fyTokenAmounts[idx], // x or ΔZ
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            uint128 resultFYTokens = YieldMath.sharesOutForFYTokenIn(
                sharesReserves,
                fyTokenReserves,
                result,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            assertSameOrSlightlyLess(resultFYTokens / 1e18, fyTokenAmounts[idx] / 1e18);
        }
    }

    /* 4. function fyTokenInForSharesOut
     *
     ***************************************************************/
    function testUnit_fyTokenInForSharesOut__baseCases() public view {
        // should match Desmos for selected inputs
        uint128[6] memory sharesAmounts = [
            uint128(50000 * 1e18),
            uint128(100_000 * 1e18),
            uint128(200_000 * 1e18),
            uint128(300_000 * 1e18),
            uint128(500_000 * 1e18),
            uint128(950_000 * 1e18)
        ];
        uint128[6] memory expectedResults = [
            uint128(55_173),
            uint128(110_393),
            uint128(220_981),
            uint128(331_770),
            uint128(554_008),
            uint128(1_058_525)
        ];
        uint128 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            result =
                YieldMath.fyTokenInForSharesOut(
                    sharesReserves,
                    fyTokenReserves,
                    sharesAmounts[idx], // x or ΔZ
                    timeTillMaturity,
                    k,
                    g2,
                    c,
                    mu
                ) /
                1e18;

            assertSameOrSlightlyMore(result, expectedResults[idx]);
        }
    }

    function testUnit_fyTokenInForSharesOut__mirror() public view {
        // should match Desmos for selected inputs
        uint128[4] memory fyTokenAmounts = [
            uint128(50000 * 1e18),
            uint128(100000 * 1e18),
            uint128(200000 * 1e18),
            uint128(1_000_000 * 1e18)
        ];
        uint128 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            result = YieldMath.sharesOutForFYTokenIn(
                sharesReserves,
                fyTokenReserves,
                fyTokenAmounts[idx], // x or ΔZ
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            uint128 resultFYTokens = YieldMath.fyTokenInForSharesOut(
                sharesReserves,
                fyTokenReserves,
                result,
                timeTillMaturity,
                k,
                g1,
                c,
                mu
            );
            assertSameOrSlightlyLess(resultFYTokens / 1e18, fyTokenAmounts[idx] / 1e18);
        }
    }
}
