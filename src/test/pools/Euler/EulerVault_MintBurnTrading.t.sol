// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

/*
  __     ___      _     _
  \ \   / (_)    | |   | | ████████╗███████╗███████╗████████╗███████╗
   \ \_/ / _  ___| | __| | ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝██╔════╝
    \   / | |/ _ \ |/ _` |    ██║   █████╗  ███████╗   ██║   ███████╗
     | |  | |  __/ | (_| |    ██║   ██╔══╝  ╚════██║   ██║   ╚════██║
     |_|  |_|\___|_|\__,_|    ██║   ███████╗███████║   ██║   ███████║
      yieldprotocol.com       ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚══════╝

*/

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//
//    NOTE:
//    These tests are exactly copy and pasted from the MintBurn.t.sol and TradingUSDC.t.sol test suites.
//    The only difference is they are setup on the PoolEuler contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../Pool/PoolErrors.sol";
import {Exp64x64} from "../../../Exp64x64.sol";
import {Math64x64} from "../../../Math64x64.sol";
import {YieldMath} from "../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../shared/Utils.sol";
import "../../shared/Constants.sol";
import {ETokenMock} from "../../mocks/ETokenMock.sol";
import {ZeroState, ZeroStateParams} from "../../shared/ZeroState.sol";
import {SyncablePoolEuler} from "../../mocks/SyncablePoolEuler.sol";
import {IERC20Like} from "../../../interfaces/IERC20Like.sol";

abstract contract ZeroStateEulerUSDC is ZeroState {
    using CastU256U128 for uint256;

    constructor() ZeroState(ZeroStateParams("USDC", "USDC", 6, "EulerVault")) {}

    //TODO: not sure where to put this fn
    // Euler eTokens always use 18 decimals so using this fn changes decimals to that of the base token,
    // for example eUSDC is converted from fp18 to fp6.
    function getSharesBalanceWithDecimalsAdjusted(address who) public returns (uint128) {
        return (shares.balanceOf(who) / pool.scaleFactor()).u128();
    }
}

contract SetFeesEulerUSDC is ZeroStateEulerUSDC {
    using Math64x64 for uint256;

    function testUnit_Euler_setFees01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee = 10001;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee));
        pool.setFees(g1Fee);
    }

    function testUnit_Euler_setFees02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee);
    }

    function testUnit_Euler_setFees03() public {
        console.log("sets valid fee");

        uint16 g1Fee = 8000;
        int128 expectedG1 = uint256(g1Fee).divu(10000);
        int128 expectedG2 = uint256(10000).divu(g1Fee);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit FeesSet(g1Fee);

        pool.setFees(g1Fee);

        assertEq(pool.g1(), expectedG1);
        assertEq(pool.g2(), expectedG2);
    }
}

abstract contract WithLiquidityEuler is ZeroStateEulerUSDC {
    function setUp() public virtual override {
        super.setUp();

        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));
        vm.prank(alice);
        pool.init(alice);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(asset.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);

        // There is a fractional amount of excess eUSDC shares in the pool.
        // as a result of the decimals mismatch between eUSDC (18) and actual USDC (6).
        // The amount is less than 2/10 of a wei of USDC: 0.000000181818181819 USDC
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();
        uint256 fractionalExcess = pool.sharesToken().balanceOf(address(pool)) - startingSharesCached * 1e12;
        assertEq(fractionalExcess, 181818181819);
        pool.retrieveShares(address(0x0)); // clear that fractional excess out for cleaner tests below
    }
}

contract Mint__ZeroStateEuler is ZeroStateEulerUSDC {
    function testUnit_Euler_mint1() public {
        console.log("adds initial liquidity");

        vm.prank(bob);
        uint256 baseIn = pool.unwrapPreview(INITIAL_EUSDC / 1e12);
        asset.mint(address(pool), baseIn);

        vm.expectEmit(true, true, true, true);

        uint256 expectedMint = 1154999999999; // mu1.05 * 1.1m rounded down
        emit Liquidity(maturity, alice, bob, address(0), int256(-1 * int256(baseIn)), int256(0), int256(expectedMint));

        vm.prank(alice);
        pool.init(bob);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);

        require(pool.balanceOf(bob) == expectedMint);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_Euler_mint2() public {
        console.log("adds liquidity with zero fyToken");
        shares.mint(address(pool), INITIAL_EUSDC);

        vm.startPrank(alice);

        pool.init(address(0));

        // After initializing, donate shares and sync to simulate having reached zero fyToken through trading
        shares.mint(address(pool), INITIAL_EUSDC);
        pool.sync();

        shares.mint(address(pool), INITIAL_EUSDC);
        pool.mint(bob, bob, 0, MAX);

        almostEqual(pool.balanceOf(bob), ((INITIAL_EUSDC / 1e12 / 2) * muNumerator) / muDenominator, 2);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    // Test intentionally ommitted.
    // function testUnit_Euler_mint3() public {
    //     console.log("syncs balances after donations");
}

contract Mint__WithLiquidityEuler is WithLiquidityEuler {
    function testUnit_Euler_mint4() public {
        console.log("mints liquidity tokens, returning shares surplus converted to asset");
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 fyTokenIn = 1e6;
        uint256 expectedMint = ((pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e6 * muNumerator) /
            muDenominator;
        uint256 expectedSharesIn = (getSharesBalanceWithDecimalsAdjusted(address(pool)) * expectedMint) /
            pool.totalSupply();

        uint256 poolTokensBefore = pool.balanceOf(bob);

        shares.mint(address(pool), (expectedSharesIn * 1e12) + 1e18); // send an extra wad of shares
        fyToken.mint(address(pool), fyTokenIn);

        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        require(shares.balanceOf(bob) == bobSharesInitialBalance);
        require(asset.balanceOf(bob) == bobAssetBefore + ETokenMock(address(shares)).convertBalanceToUnderlying(1e18)); // 1wad converted

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();

        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
}

contract Burn__WithLiquidityEuler is WithLiquidityEuler {
    function testUnit_Euler_burn1() public {
        console.log("burns liquidity tokens");
        uint256 bobAssetBefore = asset.balanceOf(address(bob));
        uint256 sharesBalance = getSharesBalanceWithDecimalsAdjusted(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = 1e6;

        address charlie = address(3);

        uint256 expectedSharesOut = (lpTokensIn * sharesBalance) / poolSup;
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);
        uint256 expectedFYTokenOut = (lpTokensIn * fyTokenBalance) / poolSup;

        // alice transfers in lp tokens then burns them
        vm.prank(alice);
        pool.transfer(address(pool), lpTokensIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            alice,
            bob,
            charlie,
            int256(expectedAssetsOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);

        uint256 assetsOut = asset.balanceOf(bob) - bobAssetBefore;
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(assetsOut, expectedAssetsOut, assetsOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(shares.balanceOf(bob) == bobSharesInitialBalance);
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}

contract MatureBurn_WithLiquidityEuler is WithLiquidityEuler {
    function testUnit_Euler_matureBurn01() public {
        console.log("burns after maturity");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 lpTokensIn = poolBalBefore;

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 expectedSharesOut = (lpTokensIn * sharesReservesBefore) / pool.totalSupply();
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);
        // fyTokenOut = lpTokensIn * realFyTokenReserves / totalSupply
        uint256 expectedFyTokenOut = (lpTokensIn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();

        vm.warp(pool.maturity());
        vm.startPrank(alice);

        pool.transfer(address(pool), lpTokensIn);
        pool.burn(alice, alice, 0, uint128(MAX));

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut + lpTokensIn); // after burning, the reserves are updated to exclude the burned lp tokens
    }
}

abstract contract WithExtraFYTokenEuler is WithLiquidityEuler {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * 1e6;
        fyToken.mint(address(pool), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(alice), 0);
    }
}

abstract contract OnceMature is WithExtraFYTokenEuler {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public override {
        super.setUp();
        vm.warp(pool.maturity());
    }
}

contract TradeUSDC__WithLiquidityEuler is WithLiquidityEuler {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_tradeUSDC01() public {
        console.log("sells a certain amount of fyToken for base");

        (uint104 sharesReserveBefore, uint104 fyTokenReserveBefore, , ) = pool.getCache();

        uint256 fyTokenIn = 25_000 * 1e6;
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(getSharesBalanceWithDecimalsAdjusted(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            uint128(fyTokenIn) * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / pool.scaleFactor();
        uint256 expectedBaseOut = pool.unwrapPreview(expectedSharesOut);

        uint256 userAssetBalanceBefore = asset.balanceOf(alice);
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, int256(expectedBaseOut), -int256(fyTokenIn));

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        uint256 userAssetBalanceAfter = asset.balanceOf(alice);
        assertEq(userAssetBalanceAfter - userAssetBalanceBefore, expectedBaseOut);

        (uint104 sharesReserveAfter, uint104 fyTokenReserveAfter, , ) = pool.getCache();
        assertEq(sharesReserveAfter, pool.getSharesBalance());
        assertEq(fyTokenReserveAfter, pool.getFYTokenBalance());

        assertEq(fyTokenReserveAfter - fyTokenReserveBefore, fyTokenIn);
        assertEq(sharesReserveBefore - sharesReserveAfter, expectedSharesOut);
    }

    function testUnit_Euler_tradeUSDC02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e6;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 999784, 340282366920938463463374607431768211455)
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_Euler_tradeUSDC03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_Euler_tradeUSDC04() public {
        console.log("buys a certain amount base for fyToken");
        (, uint104 fyTokenBalBefore, , ) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);
        uint128 sharesOut = uint128(1000e6);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(getSharesBalanceWithDecimalsAdjusted(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            sharesOut * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / pool.scaleFactor();

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, bob, bob, int256(int128(assetsOut)), -int256(expectedFYTokenIn));
        vm.prank(bob);
        pool.buyBase(bob, uint128(assetsOut), type(uint128).max);

        (, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + assetsOut);

        almostEqual(fyTokenIn, expectedFYTokenIn, sharesOut / 1000000);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_Euler_tradeUSDC05() public {

    function testUnit_Euler_tradeUSDC06() public {
        console.log("buys base and retrieves change");
        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);
        uint256 userFYTokenBefore = fyToken.balanceOf(alice);
        uint128 sharesOut = uint128(1000e6);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        fyToken.mint(address(pool), initialFYTokens);

        vm.startPrank(alice);
        pool.buyBase(bob, assetsOut, uint128(MAX));
        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + assetsOut);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > userFYTokenBefore);
    }
}

contract TradeUSDC__WithExtraFYTokenEuler is WithExtraFYTokenEuler {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_tradeUSDC07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint256 aliceBeginningSharesBal = shares.balanceOf(alice);
        uint128 sharesIn = uint128(1000e6);
        uint128 assetsIn = pool.unwrapPreview(uint256(sharesIn)).u128();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(getSharesBalanceWithDecimalsAdjusted(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        // Transfer base for sale to the pool
        asset.mint(address(pool), assetsIn);

        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            sharesIn * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / pool.scaleFactor();

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(assetsIn), int256(expectedFYTokenOut));
        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(fyTokenOut == expectedFYTokenOut);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_Euler_tradeUSDC08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(1000e6);
        uint128 baseIn = pool.unwrapPreview(sharesIn).u128();
        asset.mint(address(pool), baseIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100212520, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_Euler_tradeUSDC09() public {
        console.log("donates fyToken and sells base");
        uint128 sharesIn = uint128(10000e6);
        uint128 assetsIn = pool.unwrapPreview(sharesIn).u128();
        uint128 fyTokenDonation = uint128(5000e6);

        fyToken.mint(address(pool), fyTokenDonation);
        asset.mint(address(pool), assetsIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_Euler_tradeUSDC10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesCachedBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(1000e6);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(getSharesBalanceWithDecimalsAdjusted(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint128 assetsIn = pool.unwrapPreview(initialShares).u128();
        // Transfer shares for sale to the pool
        asset.mint(address(pool), assetsIn);

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            fyTokenOut * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / pool.scaleFactor();

        uint256 expectedBaseIn = pool.unwrapPreview(expectedSharesIn);
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(uint128(expectedBaseIn)), int256(int128(fyTokenOut)));

        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();

        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;
        uint256 sharesChange = pool.getSharesBalance() - sharesCachedCurrent;

        require(fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut, "'User2' wallet should have 1 fyToken token");

        almostEqual(sharesIn, expectedSharesIn, sharesIn / 1000000);
        require(sharesCachedCurrent + sharesChange == pool.getSharesBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_Euler_tradeUSDC11() public {

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_Euler_tradeUSDC12() public {
    //     console.log("donates base and buys fyToken");

    function testUnit_Euler_tradeUSDC13() public {
        console.log("buyBase matches buyBasePreview");

        uint128 expectedAssetOut = uint128(1000 * 10**asset.decimals());
        uint128 fyTokenIn = pool.buyBasePreview(expectedAssetOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.buyBase(alice, expectedAssetOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAssetOut, 1);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }

    function testUnit_Euler_tradeUSDC14() public {
        console.log("buyFYToken matches buyFYTokenPreview");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
        uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn);
        pool.buyFYToken(alice, fyTokenOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, expectedAssetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, fyTokenOut);
    }

    function testUnit_Euler_tradeUSDC15() public {
        console.log("sellBase matches sellBasePreview");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint256 expectedFyToken = pool.sellBasePreview(assetsIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, assetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, expectedFyToken);
    }

    function testUnit_Euler_tradeUSDC16() public {
        console.log("sellFYToken matches sellFYTokenPreview");

        uint128 fyTokenIn = uint128(1000 * 10**fyToken.decimals());
        uint128 expectedAsset = pool.sellFYTokenPreview(fyTokenIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalAfter - assetBalBefore, expectedAsset);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }
}

contract TradeUSDC__OnceMatureEuler is OnceMature {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_Euler_tradeUSDC17() internal {
        console.log("doesn't allow sellBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBase(alice, 0);
    }

    function testUnit_Euler_tradeUSDC18() internal {
        console.log("doesn't allow buyBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBase(alice, uint128(WAD), uint128(MAX));
    }

    function testUnit_Euler_tradeUSDC19() internal {
        console.log("doesn't allow sellFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYToken(alice, 0);
    }

    function testUnit_Euler_tradeUSDC20() internal {
        console.log("doesn't allow buyFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYToken(alice, uint128(WAD), uint128(MAX));
    }
}

contract AdminUSDC__WithLiquidityEuler is WithLiquidityEuler {
    function testUnit_admin1_EulerUSDC() public {
        console.log("retrieveBase returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testUnit_admin2_EulerUSDC() public {
        console.log("retrieveBase returns exceess");
        uint256 additionalAmount = 69;
        IERC20Like base = IERC20Like(address(pool.baseToken()));
        vm.prank(alice);
        base.transfer(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testUnit_admin3_EulerUSDC() public {
        console.log("retrieveShares returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveShares(alice);

        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testUnit_admin4_EulerUSDC() public {
        console.log("retrieveShares returns exceess");

        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();
        uint256 additionalAmount = 69e18;
        shares.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);

        pool.retrieveShares(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }

    function testUnit_admin5_EulerUSDC() public {
        console.log("retrieveFYToken returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testUnit_admin6_EulerUSDC() public {
        console.log("retrieveFYToken returns exceess");
        uint256 additionalAmount = 69e18;
        fyToken.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }
}

abstract contract ZeroStateEulerDAI is ZeroState {
    using CastU256U128 for uint256;

    constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "EulerVault")) {}
}

abstract contract WithLiquidityEulerDAI is ZeroStateEulerDAI {
    function setUp() public virtual override {
        super.setUp();

        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));
        vm.prank(alice);
        pool.init(alice);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(asset.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);
    }
}

contract AdminDAI__WithLiquidityEuler is WithLiquidityEulerDAI {
    function testUnit_admin1_EulerDAI() public {
        console.log("retrieveBase returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testUnit_admin2_EulerDAI() public {
        console.log("retrieveBase returns exceess");
        uint256 additionalAmount = 69;
        IERC20Like base = IERC20Like(address(pool.baseToken()));
        vm.prank(alice);
        base.transfer(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testUnit_admin3_EulerDAI() public {
        console.log("retrieveShares returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveShares(alice);

        // There is a 1 wei difference attributable to some deep nested rounding
        assertApproxEqAbs(pool.baseToken().balanceOf(alice), startingBaseBalance, 1);
        // assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testUnit_admin4_EulerDAI() public {
        console.log("retrieveShares returns exceess");

        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        uint256 additionalAmount = 69e18;
        shares.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);

        pool.retrieveShares(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);

        // There is a 1 wei difference attributable to some deep nested rounding
        assertApproxEqAbs(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount, 1);
    }

    function testUnit_admin5_EulerDAI() public {
        console.log("retrieveFYToken returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance);
        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
    }

    function testUnit_admin6_EulerDAI() public {
        console.log("retrieveFYToken returns exceess");
        uint256 additionalAmount = 69e18;
        fyToken.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }
}

abstract contract WithExtraFYTokenEulerDAI is WithLiquidityEulerDAI {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * 10**fyToken.decimals();
        fyToken.mint(address(pool), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(alice), 0);
    }
}

contract TradeDAI__WithLiquidityEuler is WithLiquidityEulerDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");

        uint256 fyTokenIn = 25_000 * 10**fyToken.decimals();
        uint256 assetBalanceBefore = asset.balanceOf(alice);
        uint256 fyTokenBalanceBefore = fyToken.balanceOf(alice);

        (uint104 sharesReserveBefore, uint104 fyTokenReserveBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            uint128(fyTokenIn) * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / pool.scaleFactor();
        uint256 expectedBaseOut = pool.unwrapPreview(expectedSharesOut);

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, int256(expectedBaseOut), -int256(fyTokenIn));

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalanceBefore, expectedBaseOut);
        assertEq(fyTokenBalanceBefore - fyToken.balanceOf(alice), fyTokenIn);

        // check pool reserves
        (uint104 sharesReserveAfter, uint104 fyTokenReserveAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReserveAfter, pool.getSharesBalance(), 1);
        assertApproxEqAbs(sharesReserveBefore - sharesReserveAfter, expectedSharesOut, 1);
        assertEq(fyTokenReserveAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReserveAfter - fyTokenReserveBefore, fyTokenIn);
    }

    function testUnit_Euler_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1 * 10**fyToken.decimals();
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellFYToken.selector,
                999785051469477285,
                340282366920938463463374607431768211455
            )
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_Euler_tradeDAI03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_Euler_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");

        uint128 sharesOut = uint128(1000 * 10**shares.decimals());
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            sharesOut * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / pool.scaleFactor();

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, int256(int128(assetsOut)), -int256(expectedFYTokenIn));

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), expectedFYTokenIn);
        pool.buyBase(alice, uint128(assetsOut), type(uint128).max);

        // check user balances
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), expectedFYTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1);
        assertEq(sharesReservesBefore - sharesReservesAfter, sharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedFYTokenIn);
    }

    // Removed
    // function testUnit_Euler_tradeDAI05() public {

    function testUnit_Euler_tradeDAI06() public {
        console.log("buys base and retrieves change");

        uint128 assetsOut = uint128(1000 * 10**asset.decimals());
        uint256 sharesOut = pool.wrapPreview(assetsOut);
        uint128 expectedFyTokenIn = pool.buyBasePreview(assetsOut);
        uint128 surplusFyTokenIn = expectedFyTokenIn * 2;

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // trade
        vm.startPrank(alice);
        fyToken.transfer(address(pool), surplusFyTokenIn); // transfer more than is required from the trade into the pool
        pool.buyBase(alice, assetsOut, uint128(MAX));

        // check user balances before retrieving
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), surplusFyTokenIn);

        pool.retrieveFYToken(alice);

        // check user balances after retrieving
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, assetsOut, 1);
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), expectedFyTokenIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, sharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedFyTokenIn);
    }
}

contract TradeDAI__WithExtraFYTokenEuler is WithExtraFYTokenEulerDAI {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_tradeDAI07() public {
        console.log("sells base (asset) for a certain amount of FYTokens");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint128 sharesIn = pool.wrapPreview(assetsIn).u128();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedFyTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            sharesIn * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / pool.scaleFactor();

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, -int128(assetsIn), int256(expectedFyTokenOut));

        // trade
        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        // check user balances
        assertApproxEqAbs(assetBalBefore - asset.balanceOf(alice), assetsIn, 1);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1);
        assertEq(sharesReservesAfter - sharesReservesBefore, sharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut);
    }

    function testUnit_Euler_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(1000 * 10**shares.decimals());
        uint128 baseIn = pool.unwrapPreview(sharesIn).u128();
        asset.mint(address(pool), baseIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellBase.selector,
                1100212520384791756398,
                340282366920938463463374607431768211455
            )
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_Euler_tradeDAI09() public {
        console.log("donates fyToken and sells base");

        uint128 assetsIn = uint128(10000 * 10**asset.decimals());
        uint128 sharesIn = pool.wrapPreview(assetsIn).u128();
        uint128 fyTokenDonation = uint128(5000 * 10**fyToken.decimals());
        uint128 expectedFyTokenOut = pool.sellBasePreview(assetsIn);
        asset.mint(address(bob), assetsIn);

        // bob's balances
        uint256 assetBalBefore = asset.balanceOf(bob);
        uint256 fyTokenBalBefore = fyToken.balanceOf(bob);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // alice donates fyToken to the pool
        vm.prank(alice);
        fyToken.transfer(address(pool), fyTokenDonation);

        // bob trades
        vm.startPrank(bob);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(bob, 0);

        // check bob's balances
        assertEq(assetBalBefore - asset.balanceOf(bob), assetsIn);
        assertEq(fyToken.balanceOf(bob) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, sharesIn, 1);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance() - fyTokenDonation); // the reserves should not take into consideration the donated fyToken
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut);
    }

    function testUnit_Euler_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base (asset)");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves * pool.scaleFactor(),
            virtFYTokenBal * pool.scaleFactor(),
            fyTokenOut * pool.scaleFactor(),
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / pool.scaleFactor();
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn);

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, alice, -int128(uint128(expectedAssetsIn)), int256(int128(fyTokenOut)));

        // trade
        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn);
        pool.buyFYToken(alice, fyTokenOut, uint128(MAX));

        // check user balances
        assertEq(assetBalBefore - asset.balanceOf(alice), expectedAssetsIn);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, fyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesAfter - sharesReservesBefore, expectedSharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, fyTokenOut);
    }
}

contract TradeDAI__PreviewFuncs is WithExtraFYTokenEulerDAI {
    function testUnit_Euler_tradeDAI11() public {
        console.log("buyBase matches buyBasePreview");

        uint128 expectedAssetOut = uint128(1000 * 10**asset.decimals());
        uint128 fyTokenIn = pool.buyBasePreview(expectedAssetOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.buyBase(alice, expectedAssetOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAssetOut, 1);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }

    function testUnit_Euler_tradeDAI12() public {
        console.log("buyFYToken matches buyFYTokenPreview");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
        uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn);
        pool.buyFYToken(alice, fyTokenOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, expectedAssetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, fyTokenOut);
    }

    function testUnit_Euler_tradeDAI13() public {
        console.log("sellBase matches sellBasePreview");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint256 expectedFyToken = pool.sellBasePreview(assetsIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, assetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, expectedFyToken);
    }

    function testUnit_Euler_tradeDAI14() public {
        console.log("sellFYToken matches sellFYTokenPreview");

        uint128 fyTokenIn = uint128(1000 * 10**fyToken.decimals());
        uint128 expectedAsset = pool.sellFYTokenPreview(fyTokenIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        fyToken.transfer(address(pool), fyTokenIn);
        pool.sellFYToken(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertApproxEqAbs(assetBalAfter - assetBalBefore, expectedAsset, 1);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }
}

contract MintWithBase__ZeroStateEulerUSDC is ZeroStateEulerUSDC {
    function testUnit_Euler_mintWithBaseUSDC01() public {
        console.log("does not mintWithBase when pool is not initialized");

        vm.expectRevert(NotInitialized.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }
}

contract MintWithBase__WithLiquidityEulerUSDC is WithLiquidityEuler {
    function testUnit_Euler_mintWithBaseUSDC02() public {
        console.log("does not mintWithBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }

    function testUnit_Euler_mintWithBaseUSDC03() public {
        console.log("mints with only base (asset)");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        // estimate how many shares need to be sold using arbitrary fyTokenToBuy amount and estimate lp tokens minted,
        // to be able to calculate how much asset to send to the pool
        uint128 fyTokenToBuy = uint128(1000 * 10**fyToken.decimals());
        // TODO fix the line below to not arbitrarily add one
        uint128 assetsToSell = pool.buyFYTokenPreview(fyTokenToBuy) + 1;
        uint256 sharesToSell = pool.wrapPreview(assetsToSell);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();

        uint256 fyTokenIn = fyToken.balanceOf(address(pool)) - realFyTokenReserves;
        // lpTokensMinted = totalSupply * (fyTokenToBuy + fyTokenIn) / realFyTokenReserves - fyTokenToBuy
        uint256 lpTokensMinted = (pool.totalSupply() * (fyTokenToBuy + fyTokenIn)) /
            (realFyTokenReserves - fyTokenToBuy);

        uint256 sharesIn = sharesToSell + ((sharesReservesBefore + sharesToSell) * lpTokensMinted) / pool.totalSupply();
        // TODO fix the line below to not arbitrarily add one
        uint256 assetsIn = pool.unwrapPreview(sharesIn) + 1;

        // mintWithBase
        vm.startPrank(alice);
        asset.transfer(address(pool), assetsIn);
        pool.mintWithBase(alice, alice, fyTokenToBuy, 0, uint128(MAX));

        // check user balances
        assertEq(assetBalBefore - asset.balanceOf(alice), assetsIn);
        assertEq(fyTokenBalBefore, fyToken.balanceOf(alice));
        assertEq(pool.balanceOf(alice) - poolBalBefore, lpTokensMinted);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesAfter - sharesReservesBefore, sharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, lpTokensMinted);
    }
}
