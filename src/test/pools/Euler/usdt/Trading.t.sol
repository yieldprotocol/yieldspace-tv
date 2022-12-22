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
//    These tests are setup on the PoolEuler contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import {ETokenMock} from "../../../mocks/ETokenMock.sol";
import {IERC20Like} from "../../../../interfaces/IERC20Like.sol";
import {TransferHelper} from "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "./State.sol";

contract Trade__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_tradeUSDT01() public {
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

    function testUnit_Euler_tradeUSDT02() public {
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
    // function testUnit_Euler_tradeUSDT03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_Euler_tradeUSDT04() public {
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

    function testUnit_Euler_tradeUSDT06() public {
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

contract Trade__WithExtraFYTokenEulerUSDT is WithExtraFYTokenEulerUSDT {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;
    using TransferHelper for IERC20Like;

    function testUnit_Euler_tradeUSDT07() public {
        console.log("sells base (asset) for a certain amount of FYTokens");

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
        deal(address(asset), address(pool), assetsIn);

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

    function testUnit_Euler_tradeUSDT08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(1000e6);
        uint128 baseIn = pool.unwrapPreview(sharesIn).u128();
        deal(address(asset), address(pool), baseIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100212520, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_Euler_tradeUSDT09() public {
        console.log("donates fyToken and sells base");
        uint128 sharesIn = uint128(10000e6);
        uint128 assetsIn = pool.unwrapPreview(sharesIn).u128();
        uint128 fyTokenDonation = uint128(5000e6);

        fyToken.mint(address(pool), fyTokenDonation);
        deal(address(asset), address(pool), assetsIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_Euler_tradeUSDT10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesReservesBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(1000e6);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(getSharesBalanceWithDecimalsAdjusted(address(pool)));
        int128 c_ = (ETokenMock(address(shares)).convertBalanceToUnderlying(1e18) * pool.scaleFactor()).fromUInt().div(
            uint256(1e18).fromUInt()
        );

        uint128 assetsIn = pool.unwrapPreview(initialShares).u128();
        // Transfer shares for sale to the pool
        deal(address(asset), address(pool), assetsIn);

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

        (uint104 sharesReservesCurrent, uint104 fyTokenReservesCurrent, , ) = pool.getCache();

        uint256 sharesIn = sharesReservesCurrent - sharesReservesBefore;
        uint256 sharesChange = pool.getSharesBalance() - sharesReservesCurrent;

        require(fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut, "'User2' wallet should have 1 fyToken token");

        almostEqual(sharesIn, expectedSharesIn, sharesIn / 1000000);
        require(sharesReservesCurrent + sharesChange == pool.getSharesBalance());
        require(fyTokenReservesCurrent == pool.getFYTokenBalance());
    }
}

contract Trade__PreviewFuncsUSDT is WithExtraFYTokenEulerUSDT {
    using TransferHelper for IERC20Like;

    function testUnit_Euler_tradeUSDT11() public {
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

    function testUnit_Euler_tradeUSDT12() public {
        console.log("buyFYToken matches buyFYTokenPreview");

        uint128 fyTokenOut = uint128(1000 * 10**fyToken.decimals());
        uint256 expectedAssetsIn = pool.buyFYTokenPreview(fyTokenOut);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        IERC20Like(address(asset)).safeTransfer(address(pool), expectedAssetsIn);
        pool.buyFYToken(alice, fyTokenOut, type(uint128).max);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, expectedAssetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, fyTokenOut);
    }

    function testUnit_Euler_tradeUSDT13() public {
        console.log("sellBase matches sellBasePreview");

        uint128 assetsIn = uint128(1000 * 10**asset.decimals());
        uint256 expectedFyToken = pool.sellBasePreview(assetsIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);

        vm.startPrank(alice);
        IERC20Like(address(asset)).safeTransfer(address(pool), assetsIn);
        pool.sellBase(alice, 0);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 fyTokenBalAfter = fyToken.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, assetsIn);
        assertEq(fyTokenBalAfter - fyTokenBalBefore, expectedFyToken);
    }

    function testUnit_Euler_tradeUSDT14() public {
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


