// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15; /*
  __     ___      _     _
  \ \   / (_)    | |   | | ████████╗███████╗███████╗████████╗███████╗
   \ \_/ / _  ___| | __| | ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    \   / | |/ _ \ |/ _` |    ██║   █████╗  ███████╗   ██║   ███████╗
     | |  | |  __/ | (_| |    ██║   ██╔══╝  ╚════██║   ██║   ╚════██║
     |_|  |_|\___|_|\__,_|    ██║   ███████╗███████║   ██║   ███████║
      yieldprotocol.com       ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚══════╝
*/

import "forge-std/Test.sol";
import {Math} from "@yield-protocol/utils-v2/src/utils/Math.sol";
import {YieldMath} from "./../YieldMath.sol";
import {YieldMathS} from "./../YieldMathS.sol";
import {Math64x64} from "./../Math64x64.sol";

/**TESTS

Links to Desmos for each formula can be found at:
https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

Tests grouped by function:
1. function fyTokenOutForSharesIn
2. function sharesInForFYTokenOut
3. function sharesOutForFYTokenIn
4. function fyTokenInForSharesOut

Each function has the following tests:
__overReserves  - test that the fn reverts if amounts are > reserves
__reverts       - try to hit each of the require statements within each function
__basecases     - test 5 scenarios comparing results to Desmos
__mirror        - FUZZ test the tokensOut of one fn can be piped to the tokensIn of the mirror fn
__noFees1       - FUZZ test the inverse of one fn reverts change from original fn -- assuming no fees
__noFees2       - FUZZ test the inverse of one fn reverts change from original fn -- assuming no fees
__isCatMaturity - FUZZ test that the value of the fn approaches C at maturity

Test name prefixe definitions:
testFail_          - Unit tests that pass if the test reverts
testUnit_          - Unit tests for common edge cases
testFuzz_          - Property based fuzz tests

All 4 trading functions were tested against eachother as follows:

                       ┌───────────────────────┬───────────────────────┬───────────────────────┬──────────────────────┐
                       │ fyTokenOutForSharesIn │ sharesInForFYTokenOut │ sharesOutForFYTokenIn │ fyTokenInForSharesOut│
┌──────────────────────┼───────────────────────┼───────────────────────┼───────────────────────┼──────────────────────┤
│                      │                       │                       │                       │                      │
│fyTokenOutForSharesIn │          X            │ fyTokenOutForSharesIn │ fyTokenOutForSharesIn │ fyTokenOutForSharesIn│
│                      │                       │ __mirror              │ __noFees1             │ __noFees2            │
├──────────────────────┼───────────────────────┼───────────────────────┼───────────────────────┼──────────────────────┤
│                      │                       │                       │                       │                      │
│sharesInForFYTokenOut │ sharesInForFYTokenOut │           X           │ sharesInForFYTokenOut │ sharesInForFYTokenOut│
│                      │ __mirror              │                       │ __noFees2             │ __noFees1            │
├──────────────────────┼───────────────────────┼───────────────────────┼───────────────────────┼──────────────────────┤
│                      │                       │                       │                       │                      │
│sharesOutForFYTokenIn │ sharesOutForFYTokenIn │ sharesOutForFYTokenIn │           X           │ sharesOutForFYTokenIn│
│                      │ __noFees1             │ __noFees2             │                       │ __mirror             │
├──────────────────────┼───────────────────────┼───────────────────────┼───────────────────────┼──────────────────────┤
│                      │                       │                       │                       │                      │
│fyTokenInForSharesOut │ fyTokenInForSharesOut │ fyTokenInForSharesOut │ fyTokenInForSharesOut │          X           │
│                      │ __noFees2             │ __noFees1             │ __mirror              │                      │
└──────────────────────┴───────────────────────┴───────────────────────┴───────────────────────┴──────────────────────┘

**********************************************************************************************************************/

contract YieldMathTest is Test {
    using Math for uint256;

    uint128 public constant fyTokenReserves = uint128(1500000 * 1e18); // Y
    uint128 public constant sharesReserves = uint128(1100000 * 1e18); // Z
    uint256 public constant totalSupply = 1_200_000e18; // s

    // The DESMOS uses 0.1 second increments, so we use them here in the tests for easy comparison.  In the deployed
    // contract we use seconds.
    uint128 public constant timeTillMaturity = uint128(90 * 24 * 60 * 60 * 10); // T

    uint256 immutable k;
    uint256 public invK = 25 * 365 * 24 * 60 * 60 * 10; // The Desmos formulas use this * 10 at the end for tenths of a second.  Pool.sol does not.

    uint256 public constant gNumerator = 95;
    uint256 public constant gDenominator = 100;
    uint256 public g1; // g to use when selling shares to pool
    uint256 public g2; // g to use when selling fyTokens to pool

    uint256 public constant cNumerator = 11;
    uint256 public constant cDenominator = 10;
    uint256 public c;

    uint256 public constant muNumerator = 105;
    uint256 public constant muDenominator = 100;
    uint256 public mu;

    constructor() {
        k = 1e18 / invK;

        g1 = gNumerator.wdiv(gDenominator);
        g2 = gDenominator.wdiv(gNumerator);
        c = cNumerator.wdiv(cDenominator);
        mu = muNumerator.wdiv(muDenominator);
    }

    function percentOrMinimum(uint256 result, uint256 divisor, uint256 nominalDiff) public pure returns (uint256) {
        uint256 fraction = result / divisor;
        return fraction > nominalDiff ? fraction : nominalDiff;
    }

    /* 1. function fyTokenOutForSharesIn
     ***************************************************************/

    function testFail_fyTokenOutForSharesIn__overReserves() public {
        // This would require more fytoken than are available, so it should revert.
        YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            1_380_000 * 1e18, // x or ΔZ Number obtained from looking at Desmos chart.
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;
    }

    function testUnit_fyTokenOutForSharesIn__reverts() public {
        // Try to hit all require statements within the function
        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            0,
            mu
        ) / 1e18;

        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            0
        ) / 1e18;

        // NOTE: could not hit "YieldMath: Rounding error" <- possibly redundant
        // NOTE: could not hit "YieldMath: > fyToken reserves" <- possibly redundant
    }

    function testUnit_fyTokenOutForSharesIn__baseCases() public {
        // should match Desmos for selected inputs
        uint256[5] memory sharesAmounts = [
            uint256(50_000 * 1e18),
            uint256(100_000 * 1e18),
            uint256(200_000 * 1e18),
            uint256(500_000 * 1e18),
            uint256(900_000 * 1e18)
        ];
        uint256[5] memory expectedResults = [
            uint256(55_113),
            uint256(110_185),
            uint256(220_202),
            uint256(549_235),
            uint256(985_292)
        ];
        uint256 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            result =
                YieldMathS.fyTokenOutForSharesIn(
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

            assertApproxEqAbs(result, expectedResults[idx], 2);
        }
    }

    function testFuzz_fyTokenOutForSharesIn__mirror(uint256 sharesAmount) public {
        // TODO: replace with actual max once YieldExtensions are merged
        sharesAmount = uint256(bound(sharesAmount, 5000000000000000000000, 1_370_000 * 1e18)); // max per desmos
        uint256 result;
        result = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        uint256 resultShares = YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            result,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        assertApproxEqAbs(resultShares / 1e18, sharesAmount / 1e18, 1);
    }

    function testFuzz_fyTokenOutForSharesIn__noFees1(uint256 sharesAmount) public {
        sharesAmount = uint256(bound(sharesAmount, 5000000000000000000000, 1_370_000 * 1e18));
        uint256 result;
        result = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves + sharesAmount,
            fyTokenReserves - result,
            result,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        assertApproxEqAbs(result2 / 1e18, sharesAmount / 1e18, 1);
    }

    function testFuzz_fyTokenOutForSharesIn__noFees2(uint256 sharesAmount) public {
        sharesAmount = uint256(bound(sharesAmount, 5000000000000000000000, 1_370_000 * 1e18));
        uint256 result;
        result = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.fyTokenInForSharesOut(
            sharesReserves + sharesAmount,
            fyTokenReserves - result,
            sharesAmount,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        require(result / 1e18 == result2 / 1e18);
    }

    function testFuzz_fyTokenOutForSharesIn__isCatMaturity(uint256 sharesAmount) public {
        // At maturity the fytoken price will be close to c
        // TODO: replace with actual max once YieldExtensions are merged
        // max per desmos = 1.367m -- anything higher will result in more han 1.5m fyTokens out
        sharesAmount = uint256(bound(sharesAmount, 500000000000000000000, 1_360_000 * 1e18));
        uint256 result = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            0,
            k,
            YieldMathS.WAD,
            c,
            mu
        ) / 1e18;

        uint256 cPrice = ((cNumerator * sharesAmount) / cDenominator) / 1e18;

        assertApproxEqAbs(result, cPrice, 2);
    }

    function testFuzz_fyTokenOutForSharesIn_farFromMaturity(uint256 sharesAmount) public {
        // asserts that when time to maturity is approaching 100% the result is the same as UniV2 style constant product amm
        sharesAmount = uint256(bound(sharesAmount, 500000000000000000000, 1_370_000 * 1e18));
        uint256 result = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            25 * 365 * 24 * 60 * 60 * 10 - 10,
            k,
            YieldMathS.WAD, // set fees to 0
            YieldMath.WAD, // set c to 1
            YieldMath.WAD //  set mu to 1
        );
        uint256 oldK = uint256(fyTokenReserves) * uint256(sharesReserves);

        uint256 newSharesReserves = sharesReserves + sharesAmount;
        uint256 newFyTokenReserves = oldK / newSharesReserves;
        uint256 ammFyOut = fyTokenReserves - newFyTokenReserves;

        console.log("ammFyOut", ammFyOut);
        console.log("result", result);
        assertApproxEqAbs(ammFyOut / 1e18, result / 1e18, percentOrMinimum(result, 1e20, 2));
    }

    // // function testUnit_fyTokenOutForSharesIn__increaseG(uint128 amount) public {
    // function testUnit_fyTokenOutForSharesIn__increaseG() public {
    //     uint128 amount = uint128(969274532731510217051237);
    // TODO: replace with actual max once YieldExtensions are merged
    //     // amount = uint128(bound(amount, 5000000000000000000000, 1_370_000 * 1e18)); // max per desmos
    //     uint128 result1 = YieldMath.fyTokenOutForSharesIn(
    //         sharesReserves,
    //         fyTokenReserves,
    //         amount,
    //         timeTillMaturity,
    //         k,
    //         g1,
    //         c,
    //         mu
    //     ) / 1e18;
    //     int128 bumpedG = uint256(975).fromUInt().div((10 * gDenominator).fromUInt());
    //     uint128 result2 = YieldMath.fyTokenOutForSharesIn(
    //         sharesReserves,
    //         fyTokenReserves,
    //         amount,
    //         timeTillMaturity,
    //         k,
    //         bumpedG,
    //         c,
    //         mu
    //     ) / 1e18;
    //     require(result2 >= result1);
    // }

    /* 2. function sharesInForFYTokenOut
     ***************************************************************/

    function testFail_sharesInForFYTokenOut__overReserves() public {
        // Per desmos, this would require more fytoken than are available, so it should revert.
        YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            1_501_000, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;


        // NOTE: could not hit "YieldMath: > fyToken reserves" <- possibly redundant
    }

    function testUnit_sharesInForFYTokenOut__reverts() public {
        // Try to hit all require statements within the function
        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            0,
            mu
        ) / 1e18;

        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            0
        ) / 1e18;

        vm.expectRevert(YieldMathS.UnderflowYXA.selector);
        YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            type(uint256).max,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;

        // NOTE: could not hit "YieldMath: Rate overflow (zyy)" <- possibly redundant
    }

    function testUnit_sharesInForFYTokenOut__baseCases() public {
        // should match Desmos for selected inputs
        uint256[4] memory fyTokenAmounts = [
            uint256(50000 * 1e18),
            uint256(100_000 * 1e18),
            uint256(200_000 * 1e18),
            uint256(900_000 * 1e18)
        ];
        uint256[4] memory expectedResults = [
            uint256(45359),
            uint256(90_749),
            uint256(181_625),
            uint256(821_505)
        ];
        uint256 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            result =
                YieldMathS.sharesInForFYTokenOut(
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

            assertApproxEqAbs(result, expectedResults[idx], 2);
        }
    }

    function testFuzz_sharesInForFYTokenOut__mirror(uint256 fyTokenAmount) public {
        // TODO: replace with actual max once YieldExtensions are merged
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_370_000 * 1e18)); // max per desmos
        uint256 result = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        uint256 resultFYTokens = YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            result,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        assertApproxEqAbs(resultFYTokens / 1e18, fyTokenAmount / 1e18, 2);
    }

    function testFuzz_sharesInForFYTokenOut__noFees1(uint256 fyTokenAmount) public {
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_370_000 * 1e18));
        uint256 result;
        result = YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.fyTokenInForSharesOut(
            sharesReserves + result,
            fyTokenReserves - fyTokenAmount,
            result,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        assertApproxEqAbs(result2 / 1e18, fyTokenAmount / 1e18, 2);
    }

    function testFuzz_sharesInForFYTokenOut__noFees2(uint256 fyTokenAmount) public {
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_370_000 * 1e18));
        uint256 result;
        result = YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves + result,
            fyTokenReserves - fyTokenAmount,
            fyTokenAmount,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        require(result / 1e18 == result2 / 1e18);
    }

    function testFuzz_sharesInForFYTokenOut__isCatMaturity(uint256 fyTokenAmount) public {
        // At maturity the fytoken price will be close to c
        fyTokenAmount = uint256(bound(fyTokenAmount, 500000000000000000000, 1_370_000 * 1e18));
        uint256 result = YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            0,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        uint256 cPrice = (cNumerator * result) / cDenominator;

        assertApproxEqAbs(fyTokenAmount / 1e18, cPrice / 1e18, 2);
    }

    // NOTE: testFuzz_sharesInForFYTokenOut_farFromMaturity cannot be implemented because the size of
    // time to maturity creates an overflow in the final step of the function.

    /* 3. function sharesOutForFYTokenIn
     ***************************************************************/

    function testFail_sharesOutForFYTokenIn__overReserves() public {
        // should match Desmos for selected inputs
        YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_240_000 * 1e18, // x or ΔZ  adjusted up from desmos to account for normalization
            timeTillMaturity,
            k,
            g2,
            c,
            mu
        ) / 1e18;
    }

    function testUnit_sharesOutForFYTokenIn__reverts() public {
        // Try to hit all require statements within the function

        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            0,
            mu
        ) / 1e18;

        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            0
        ) / 1e18;

        // NOTE: could not hit "YieldMath: Rate underflow" <- possibly redundant
    }

    function testUnit_sharesOutForFYTokenIn__baseCases() public {
        // should match Desmos for selected inputs
        uint256[5] memory fyTokenAmounts = [
            uint256(25000 * 1e18),
            uint256(50_000 * 1e18),
            uint256(100_000 * 1e18),
            uint256(200_000 * 1e18),
            uint256(500_000 * 10 ** 18)
        ];
        uint256[5] memory expectedResults = [
            uint256(22_661),
            uint256(45_313),
            uint256(90_592),
            uint256(181_041),
            uint256(451_473)
        ];
        uint256 result;
        for (uint256 idx; idx < fyTokenAmounts.length; idx++) {
            result =
                YieldMathS.sharesOutForFYTokenIn(
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

            assertApproxEqAbs(result, expectedResults[idx], 2);
        }
    }

    function testFuzz_sharesOutForFYTokenIn__mirror(uint256 fyTokenAmount) public {
        // TODO: replace with actual max once YieldExtensions are merged
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_100_000 * 1e18)); // max per desmos
        // should match Desmos for selected inputs
        uint256 result = YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        uint256 resultFYTokens = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            result,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        assertApproxEqAbs(resultFYTokens / 1e18, fyTokenAmount / 1e18, 2);
    }

    function testFuzz_sharesOutForFYTokenIn__noFees1(uint256 fyTokenAmount) public {
        // TODO: replace with actual max once YieldExtensions are merged
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_100_000 * 1e18)); // max per desmos

        uint256 result = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves - result,
            fyTokenReserves + fyTokenAmount,
            result,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        assertApproxEqAbs(result2 / 1e18, fyTokenAmount / 1e18, 1);
    }

    function testFuzz_sharesOutForFYTokenIn__noFees2(uint256 fyTokenAmount) public {
        // TODO: replace with actual max once YieldExtensions are merged
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_100_000 * 1e18)); // max per desmos

        uint256 result = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.sharesInForFYTokenOut(
            sharesReserves - result,
            fyTokenReserves + fyTokenAmount,
            fyTokenAmount,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        require(result / 1e18 == result2 / 1e18);
    }

    function testFuzz_sharesOutForFYTokenIn__isCatMaturity(uint256 fyTokenAmount) public {
        // At maturity the fytoken price will be close to c
        fyTokenAmount = uint256(bound(fyTokenAmount, 500000000000000000000, 1_100_000 * 1e18));
        uint256 result = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            0,
            k,
            YieldMathS.WAD,
            c,
            mu
        );

        uint256 cPrice = (cNumerator * result) / cDenominator;

        assertApproxEqAbs(fyTokenAmount / 1e18, cPrice / 1e18, 1);
    }

    // NOTE: testFuzz_sharesOutForFYTokenIn_farFromMaturity cannot be implemented because the size of
    // time to maturity creates an overflow in the final step of the function.

    /* 4. function fyTokenInForSharesOut
     *
     ***************************************************************/
    function testFail_fyTokenInForSharesOut__overReserves() public {
        YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            1_101_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g2,
            c,
            mu
        ) / 1e18;
    }

    function testUnit_fyTokenInForSharesOut__reverts() public {
        // Try to hit all require statements within the function

        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            0,
            mu
        ) / 1e18;

        vm.expectRevert(YieldMathS.CAndMuMustBePositive.selector);
        YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            0
        ) / 1e18;

        vm.expectRevert(YieldMathS.TooManySharesIn.selector);
        YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18,
            timeTillMaturity,
            k,
            g1,
            1e12,
            1
        ) / 1e18;

        // NOTE: could not hit "YieldMath: > fyToken reserves" <- possibly redundant
    }

    function testUnit_fyTokenInForSharesOut__baseCases() public {
        // should match Desmos for selected inputs
        uint256[6] memory sharesAmounts = [
            uint256(50000 * 1e18),
            uint256(100_000 * 1e18),
            uint256(200_000 * 1e18),
            uint256(300_000 * 1e18),
            uint256(500_000 * 1e18),
            uint256(950_000 * 1e18)
        ];
        uint256[6] memory expectedResults = [
            uint256(55_173),
            uint256(110_393),
            uint256(220_981),
            uint256(331_770),
            uint256(554_008),
            uint256(1_058_525)
        ];
        uint256 result;
        for (uint256 idx; idx < sharesAmounts.length; idx++) {
            result =
                YieldMathS.fyTokenInForSharesOut(
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

            assertApproxEqAbs(result, expectedResults[idx], 2);
        }
    }

    function testFuzz_fyTokenInForSharesOut__mirror(uint256 fyTokenAmount) public {
        fyTokenAmount = uint256(bound(fyTokenAmount, 5000000000000000000000, 1_100_000 * 1e18));
        uint256 result = YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        uint256 resultFYTokens = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            result,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
        assertApproxEqAbs(resultFYTokens / 1e18, fyTokenAmount / 1e18, 2);
    }

    function testFuzz_fyTokenInForSharesOut__noFees1(uint256 sharesAmount) public {
        sharesAmount = uint256(bound(sharesAmount, 5000000000000000000000, 1_100_000 * 1e18));
        uint256 result = YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.sharesInForFYTokenOut(
            sharesReserves - sharesAmount,
            fyTokenReserves + result,
            result,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        assertApproxEqAbs(result2 / 1e18, sharesAmount / 1e18, 2);
    }

    function testFuzz_fyTokenInForSharesOut__noFees2(uint256 sharesAmount) public {
        sharesAmount = uint256(bound(sharesAmount, 5000000000000000000000, 1_100_000 * 1e18));
        uint256 result = YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 result2 = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves - sharesAmount,
            fyTokenReserves + result,
            sharesAmount,
            timeTillMaturity,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        console.log(
            "+ + file: YieldMath.t.sol + line 1071 + testUnit_fyTokenInForSharesOut__noFees2 + result2",
            result2
        );
        require(result2 / 1e18 == result / 1e18);
    }

    function testFuzz_fyTokenInForSharesOut__isCatMaturity(uint256 sharesAmount) public {
        // At maturity the fytoken price will be close to c
        sharesAmount = uint256(bound(sharesAmount, 500000000000000000000, 1_100_000 * 1e18));
        uint256 result = YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            0,
            k,
            YieldMathS.WAD,
            c,
            mu
        );
        uint256 cPrice = (cNumerator * sharesAmount) / cDenominator;
        assertApproxEqAbs(result / 1e18, cPrice / 1e18, 1);
    }

    function testFuzz_fyTokenInForSharesOut_farFromMaturity(uint256 sharesAmount) public {
        // asserts that when time to maturity is approaching 100% the result is the same as UniV2 style constant product amm
        sharesAmount = uint256(bound(sharesAmount, 500000000000000000000, 1_100_000 * 1e18));
        uint256 result = YieldMathS.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            25 * 365 * 24 * 60 * 60 * 10 - 10,
            k,
            YieldMathS.WAD, // set fees to 0
            YieldMathS.WAD, // set c to 1
            YieldMathS.WAD //  set mu to 1
        );
        uint256 oldK = uint256(fyTokenReserves) * uint256(sharesReserves);

        uint256 newSharesReserves = sharesReserves - sharesAmount;
        uint256 newFyTokenReserves = oldK / newSharesReserves;
        uint256 ammFyIn = newFyTokenReserves - fyTokenReserves;

        assertApproxEqAbs(ammFyIn / 1e18, result / 1e18, percentOrMinimum(result, 1e20, 2));
    }

    /* 5. function maxFYTokenIn
     ***************************************************************/

    function test_maxFYTokenIn() public {
        uint256 _maxFYTokenIn = YieldMathS.maxFYTokenIn(
            sharesReserves, 
            fyTokenReserves, 
            timeTillMaturity,
            k,
            g2,
            c,
            mu
        );
        // https://www.desmos.com/calculator/jcdfr1qv3z
        assertApproxEqAbs(_maxFYTokenIn, 1230211.59495e18, 1e15); // 

        uint256 sharesOut = YieldMathS.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            _maxFYTokenIn,
            timeTillMaturity,
            k,
            g2,
            c,
            mu
        );

        assertApproxEqAbs(sharesOut, sharesReserves, 1e12);
    }

    /* 6. function maxFYTokenOut
     ***************************************************************/

    function test_maxFYTokenOut() public {
        uint256 _maxFYTokenOut = YieldMathS.maxFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        // https://www.desmos.com/calculator/yfngmdxnsg
        assertApproxEqAbs(_maxFYTokenOut, 176616.991033e18, 1e12);

        uint256 sharesIn = YieldMathS.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            _maxFYTokenOut,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        _maxFYTokenOut = YieldMathS.maxFYTokenOut(
            sharesReserves + sharesIn,
            fyTokenReserves - _maxFYTokenOut,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        assertApproxEqAbs(_maxFYTokenOut, 0, 1e12); // It would be better to verify the pool can't trade any more fyTokens without using YieldMathS.maxFYTokenOut
    }

    /* 7. function maxSharesIn
     ***************************************************************/

    function test_maxSharesIn() public {
        uint256 _maxSharesIn = YieldMathS.maxSharesIn(
            sharesReserves,
            fyTokenReserves,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        // https://www.desmos.com/calculator/oddzrif0y7
        assertApproxEqAbs(_maxSharesIn, 160364.770445e18, 1e12);

        uint256 fyTokenOut = YieldMathS.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            _maxSharesIn,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        uint256 _maxFYTokenOut = YieldMathS.maxFYTokenOut(
            sharesReserves + _maxSharesIn,
            fyTokenReserves - fyTokenOut,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );

        assertApproxEqAbs(_maxFYTokenOut, 0, 1e12); // It would be better to verify the pool can't trade any more without using YieldMathS.maxSharesIn
    }

    /* 8. function invariant
     ***************************************************************/

    function test_invariant() public {
        uint256 result = YieldMathS.invariant(
            sharesReserves,
            fyTokenReserves,
            totalSupply,
            timeTillMaturity,
            k,
            g2,
            c,
            mu
        );

        // https://www.desmos.com/calculator/tl0of4wrju
        assertApproxEqAbs(result, 1.1553244e18, 1e15); // TODO: Fuzz test that the invariant growth with sequential trades is continuous
    }
}
