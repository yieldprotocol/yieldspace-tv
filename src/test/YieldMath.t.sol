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

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Exp64x64} from "./../Exp64x64.sol";
import {YieldMath} from "./../YieldMath.sol";
import {Math64x64} from "./../Math64x64.sol";

import "./helpers.sol";

contract YieldMathTest is Test {
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
        testFuzz_          - Property based fuzz tests

    ******************************************************************************************************************/

    uint128 public constant sharesReserves = uint128(1100000 * 1e18); // Z
    uint128 public constant fyTokenReserves = uint128(1500000 * 1e18); // Y

    // The DESMOS uses 0.1 second increments, so we use them here in the tests for easy comparison.  In the deployed
    // contract we use seconds.
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
        // The Desmos formulas use this * 10 at the end for tenths of a second.  Pool.sol does not.
        uint256 invK = 25 * 365 * 24 * 60 * 60 * 10;
        k = uint256(1).fromUInt().div(invK.fromUInt());

        g1 = gNumerator.fromUInt().div(gDenominator.fromUInt());
        g2 = gDenominator.fromUInt().div(gNumerator.fromUInt());
        c = cNumerator.fromUInt().div(cDenominator.fromUInt());
        mu = muNumerator.fromUInt().div(muDenominator.fromUInt());
    }

    function assertSameOrSlightlyLess(uint128 result, uint128 expectedResult) public pure {
        require((expectedResult - result) <= 2);
    }

    function assertSameOrSlightlyMore(uint128 result, uint128 expectedResult) public pure {
        require((result - expectedResult) <= 2);
    }

    /* 1. function fyTokenOutForSharesIn
     ***************************************************************/

    function testFail_fyTokenOutForSharesIn__overReserves() public view {
        // This would require more fytoken than are available, so it should revert.
        YieldMath.fyTokenOutForSharesIn(
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

    function testUnit_fyTokenOutForSharesIn__mirror(uint128 sharesAmount) public {
        vm.assume(sharesAmount > 10000000000000000000 && sharesAmount < (1_379_000 * 1e18)); // max per desmos
        uint128 result;
        result = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
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

        require(resultShares / 1e18 == sharesAmount / 1e18);
    }

    function testUnit_fyTokenOutForSharesIn__noFees1(uint128 sharesAmount) public {
        vm.assume(sharesAmount > 10000000000000000000 && sharesAmount < (1_379_000 * 1e18));
        uint128 result;
        result = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.sharesOutForFYTokenIn(
            sharesReserves + sharesAmount,
            fyTokenReserves - result,
            result,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        require(result2 / 1e18 == sharesAmount / 1e18);
    }

    function testUnit_fyTokenOutForSharesIn__noFees2(uint128 sharesAmount) public {
        vm.assume(sharesAmount > 10000000000000000000 && sharesAmount < (1_379_000 * 1e18));
        uint128 result;
        result = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.fyTokenInForSharesOut(
            sharesReserves + sharesAmount,
            fyTokenReserves - result,
            sharesAmount,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        require(result / 1e18 == result2 / 1e18);
    }

    function test_fyTokenOutForSharesIn_isCatMaturity(uint128 sharesAmount) public {
        // At maturity the fytoken price will be close to c
        vm.assume(sharesAmount > 1000000000000000000 && sharesAmount < (1_370_000 * 1e18));
        uint128 result = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            0,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        ) / 1e18;

        uint256 cPrice = ((cNumerator * sharesAmount) / cDenominator) / 1e18;

        require(result == cPrice);
    }

    // function testUnit_fyTokenOutForSharesIn__increaseG(uint128 amount, uint16 g_) public {
    //     // as G approaches 1, less fees are charged so the amount of fyToken should increase
    //     vm.assume(amount > 10000000000000000000 && amount < (1_379_000 * 1e18));
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

    //     console.log("+ + file: YieldMath.t.sol + line 191 + testUnit_fyTokenOutForSharesIn__increaseG + uint256(950 + g_ % 50)", uint256(950 + g_ % 50));
    //     console.log("+ + file: YieldMath.t.sol + line 191 + testUnit_fyTokenOutForSharesIn__increaseG + gDenominator * 10", gDenominator * 10);
    //     int128 bumpedG = uint256(950 + g_ % 50).fromUInt().div((gDenominator * 10).fromUInt());
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

    // function test_fyTokenOutForSharesIn_farFromMaturity() public {
    //     // TODO: convert to fuzz
    //     // function testFuzz_fyTokenOutForSharesIn_farFromMaturity(uint128 sharesAmount) public {
    //     // asserts that the fyToken out will always be more than the shares in
    //     // vm.assume(sharesAmount > 1000000000000000000 && sharesAmount < (1_379_000 * 1e18));
    //     uint128 sharesAmount = 50_000 * 1e18;
    //     uint128 result = YieldMath.fyTokenOutForSharesIn(
    //         sharesReserves,
    //         fyTokenReserves,
    //         sharesAmount, // x or ΔZ
    //         timeTillMaturity,
    //         k,
    //         g1,
    //         c,
    //         mu
    //     );
    //     uint256 oldK = uint256(fyTokenReserves) * uint256(sharesReserves) / 1e18;

    //     uint256 newSharesReserves = sharesReserves + sharesAmount;
    //     console.log("+ + file: YieldMath.t.sol + line 235 + testFuzz_fyTokenOutForSharesIn_farFromMaturity + newSharesReserves", newSharesReserves);
    //     console.log("+ + file: YieldMath.t.sol + line 237 + testFuzz_fyTokenOutForSharesIn_farFromMaturity + (oldK * 1e18)", (oldK * 1e18));
    //     uint256 newFyTokenReserves = (oldK * 1e18) / newSharesReserves;
    //     uint256 ammFyOut = fyTokenReserves - newFyTokenReserves;

    //     console.log('result', result);
    //     console.log('ammFyOut', ammFyOut);

    // }

    /* 2. function sharesInForFYTokenOut
     ***************************************************************/

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

        vm.expectRevert(bytes("YieldMath: Rounding error"));
        YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            100000,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;

        // TODO: could not hit "YieldMath: > fyToken reserves" <- possibly redundant

    }

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

    function testUnit_sharesInForFYTokenOut__mirror(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_379_000 * 1e18)); // max per desmos
        uint128 result = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        );
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
        assertSameOrSlightlyMore(resultFYTokens / 1e18, fyTokenAmount / 1e18);
    }

    function testUnit_sharesInForFYTokenOut__noFees1(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_379_000 * 1e18));
        uint128 result;
        result = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.fyTokenInForSharesOut(
            sharesReserves + result,
            fyTokenReserves - fyTokenAmount,
            result,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        require(result2 / 1e18 == fyTokenAmount / 1e18);
    }

    function testUnit_sharesInForFYTokenOut__noFees2(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_379_000 * 1e18));
        uint128 result;
        result = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.sharesOutForFYTokenIn(
            sharesReserves + result,
            fyTokenReserves - fyTokenAmount,
            fyTokenAmount,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        require(result / 1e18 == result2 / 1e18);
    }

    function test_sharesInForFYTokenOut_isCatMaturity(uint128 fyTokenAmount) public {
        // At maturity the fytoken price will be close to c
        vm.assume(fyTokenAmount > 1000000000000000000 && fyTokenAmount < (1_370_000 * 1e18));
        uint128 result = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            0,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        uint256 cPrice = (cNumerator * result) / cDenominator;

        require(fyTokenAmount / 1e18 == cPrice / 1e18);
    }


    /* 3. function sharesOutForFYTokenIn
     ***************************************************************/

    function testFail_sharesOutForFYTokenIn__overReserves() public view {
        // should match Desmos for selected inputs
        YieldMath.sharesOutForFYTokenIn(
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

    function testUnit_sharesOutForFYTokenIn__mirror(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_100_000 * 1e18)); // max per desmos
        // should match Desmos for selected inputs
        uint128 result= YieldMath.fyTokenInForSharesOut(
                sharesReserves,
                fyTokenReserves,
                fyTokenAmount, // x or ΔZ
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
            assertSameOrSlightlyLess(resultFYTokens / 1e18, fyTokenAmount / 1e18);
    }

    function testUnit_sharesOutForFYTokenIn__noFees1(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_100_000 * 1e18)); // max per desmos

        uint128 result = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.fyTokenOutForSharesIn(
            sharesReserves - result,
            fyTokenReserves + fyTokenAmount,
            result,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        require(result2 / 1e18 == fyTokenAmount / 1e18);
    }

    function testUnit_sharesOutForFYTokenIn__noFees2(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_100_000 * 1e18)); // max per desmos

        uint128 result = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.sharesInForFYTokenOut(
            sharesReserves - result,
            fyTokenReserves + fyTokenAmount,
            fyTokenAmount,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        require(result / 1e18 == result2 / 1e18);
    }

    function test_sharesOutForFYTokenIn_isCatMaturity(uint128 fyTokenAmount) public {
        // At maturity the fytoken price will be close to c
        vm.assume(fyTokenAmount > 1000000000000000000 && fyTokenAmount < (1_100_000 * 1e18));
        uint128 result = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            fyTokenAmount, // x or ΔZ
            0,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        uint256 cPrice = (cNumerator * result) / cDenominator;

        require(fyTokenAmount / 1e18 == cPrice / 1e18);
    }


    function testUnit_sharesOutForFYTokenIn__reverts() public {

        vm.expectRevert(bytes("YieldMath: c and mu must be positive"));
        YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            0,
            mu
        ) / 1e18;

        vm.expectRevert(bytes("YieldMath: c and mu must be positive"));
        YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            0
        ) / 1e18;

        vm.expectRevert(bytes("YieldMath: Rate overflow (nsr)"));
        YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            c,
            type(int128).max
        ) / 1e18;

        vm.expectRevert(bytes("YieldMath: Rate overflow (za)"));
        YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            fyTokenReserves,
            1_500_000 * 1e18, // x or ΔZ
            timeTillMaturity,
            k,
            g1,
            type(int128).max,
            0x10000000000000000
        ) / 1e18;

        vm.expectRevert(bytes("YieldMath: Rate overflow (yxa)"));
        YieldMath.sharesOutForFYTokenIn(
            50000,
            fyTokenReserves,
            1_500_000 * 1e18,
            timeTillMaturity,
            k,
            g1,
            c,
            mu
        ) / 1e18;

        // TODO: could not hit "YieldMath: Rate underflow" <- possibly redundant


    }

    /* 4. function fyTokenInForSharesOut
     *
     ***************************************************************/
    function testFail_fyTokenInForSharesOut__overReserves() public view {
        YieldMath.fyTokenInForSharesOut(
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

    function testUnit_fyTokenInForSharesOut__mirror(uint128 fyTokenAmount) public {
        vm.assume(fyTokenAmount > 10000000000000000000 && fyTokenAmount < (1_100_000 * 1e18));
        uint128 result = YieldMath.fyTokenInForSharesOut(
                sharesReserves,
                fyTokenReserves,
                fyTokenAmount, // x or ΔZ
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
            assertSameOrSlightlyLess(resultFYTokens / 1e18, fyTokenAmount / 1e18);
    }

    function testUnit_fyTokenInForSharesOut__noFees1(uint128 sharesAmount) public {
        vm.assume(sharesAmount > 10000000000000000000 && sharesAmount < (1_100_000 * 1e18));
        uint128 result= YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.sharesInForFYTokenOut(
            sharesReserves - sharesAmount,
            fyTokenReserves + result,
            result,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        require(result2 / 1e18 == sharesAmount / 1e18);
    }

    function testUnit_fyTokenInForSharesOut__noFees2(uint128 sharesAmount) public {
        vm.assume(sharesAmount > 10000000000000000000 && sharesAmount < (1_100_000 * 1e18));
        uint128 result= YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        uint128 result2 = YieldMath.fyTokenOutForSharesIn(
            sharesReserves - sharesAmount,
            fyTokenReserves + result,
            sharesAmount,
            timeTillMaturity,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );
        require(result2 / 1e18 == result / 1e18);
    }

    function test_fyTokenInForSharesOut_isCatMaturity(uint128 sharesAmount) public {
        // At maturity the fytoken price will be close to c
        vm.assume(sharesAmount > 1000000000000000000 && sharesAmount < (1_100_000 * 1e18));
        uint128 result = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            fyTokenReserves,
            sharesAmount, // x or ΔZ
            0,
            k,
            int128(YieldMath.ONE),
            c,
            mu
        );

        uint256 cPrice = (cNumerator * sharesAmount) / cDenominator;
        require(result / 1e18 == cPrice / 1e18);
    }

}
