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
//    These tests are exactly copy and pasted from the MintBurn.t.sol test suites.
//    These tests run in a mainnet fork environment.
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../Pool/PoolErrors.sol";
import {IPool, IERC20Like as IERC20Metadata} from "../../../../Pool/PoolImports.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import "./State.sol";

contract SetFeesEulerDAIFork is EulerDAIFork {
    using Math64x64 for uint256;

    function testForkUnit_Euler_setFeesDAI01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee_ = 10001;

        vm.prank(timelock);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee_));
        pool.setFees(g1Fee_);
    }

    function testForkUnit_Euler_setFeesDAI02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee_ = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee_);
    }

    function testForkUnit_Euler_setFeesDAI03() public {
        console.log("sets valid fee");

        uint16 g1Fee_ = 8000;
        int128 expectedG1 = uint256(g1Fee_).divu(10000);
        int128 expectedG2 = uint256(10000).divu(g1Fee_);

        vm.prank(timelock);
        vm.expectEmit(true, true, true, true);
        emit FeesSet(g1Fee_);

        pool.setFees(g1Fee_);

        assertEq(pool.g1(), expectedG1);
        assertEq(pool.g2(), expectedG2);
    }
}

contract Mint__WithLiquidityEulerDAIFork is EulerDAIFork {
    function testForkUnit_Euler_mintDAI03() public {
        console.log("mints liquidity tokens, returning shares surplus converted to asset");

        uint256 fyTokenIn = 1000 * 10**fyToken.decimals();
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();

        // lpTokensMinted = totalSupply * fyTokenIn / realFyTokenReserves
        uint256 expectedMint = (pool.totalSupply() * fyTokenIn) / realFyTokenReserves;
        // expectedSharesIn = sharesReserves * lpTokensMinted / totalSupply
        uint256 expectedSharesIn = (sharesReservesBefore * expectedMint) / pool.totalSupply();
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn);

        // pool mint
        vm.startPrank(alice);
        asset.transfer(address(pool), expectedAssetsIn * 2); // alice sends too many assets
        fyToken.transfer(address(pool), fyTokenIn);
        pool.mint(alice, alice, 0, MAX);

        // check user balances
        assertApproxEqAbs(assetBalBefore - asset.balanceOf(alice), expectedAssetsIn, 1); // alice sent too many assets, but still gets back surplus
        assertEq(fyTokenBalBefore - fyToken.balanceOf(alice), fyTokenIn);
        assertEq(pool.balanceOf(alice) - poolBalBefore, expectedMint);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1);
        assertEq(sharesReservesAfter - sharesReservesBefore, expectedSharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, fyTokenIn + expectedMint);
    }
}

contract Burn__WithLiquidityEulerDAIFork is EulerDAIForkWithLiquidity {
    function testForkUnit_Euler_burnDAI01() public {
        console.log("burns liquidity tokens");

        uint256 lpTokensIn = 1000 * 10**asset.decimals(); // using asset decimals here, since they match the pool
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 expectedSharesOut = (lpTokensIn * sharesReservesBefore) / pool.totalSupply();
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);
        uint256 expectedFyTokenOut = (lpTokensIn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();

        vm.startPrank(alice);
        pool.transfer(address(pool), lpTokensIn);

        // burn
        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            pool.maturity(),
            alice,
            alice,
            alice,
            int256(expectedAssetsOut),
            int256(expectedFyTokenOut),
            -int256(lpTokensIn)
        );
        pool.burn(alice, alice, 0, MAX);

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);
        assertEq(poolBalBefore - pool.balanceOf(alice), lpTokensIn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut + lpTokensIn);
    }
}

contract MatureBurn_WithLiquidityEulerDAIFork is EulerDAIFork {
    function testForkUnit_Euler_matureBurn01() public {
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

contract MintWithBase__WithLiquidityEulerDAIFork is EulerDAIFork {
    function testForkUnit_Euler_mintWithBaseDAI02() public {
        console.log("does not mintWithBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }

    function testForkUnit_Euler_mintWithBaseDAI03() public {
        console.log("mints with only base (asset)");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        // estimate how many shares need to be sold using arbitrary fyTokenToBuy amount and estimate lp tokens minted,
        // to be able to calculate how much asset to send to the pool
        uint128 fyTokenToBuy = uint128(1000 * 10**fyToken.decimals());
        uint128 assetsToSell = pool.buyFYTokenPreview(fyTokenToBuy);
        uint256 sharesToSell = pool.wrapPreview(assetsToSell);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();

        uint256 fyTokenIn = fyToken.balanceOf(address(pool)) - realFyTokenReserves;
        // lpTokensMinted = totalSupply * (fyTokenToBuy + fyTokenIn) / realFyTokenReserves - fyTokenToBuy
        uint256 lpTokensMinted = (pool.totalSupply() * (fyTokenToBuy + fyTokenIn)) /
            (realFyTokenReserves - fyTokenToBuy);

        uint256 sharesIn = sharesToSell + ((sharesReservesBefore + sharesToSell) * lpTokensMinted) / pool.totalSupply();
        uint256 assetsIn = pool.unwrapPreview(sharesIn);

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

contract BurnForBase__WithLiquidityEulerDAIFork is EulerDAIForkWithLiquidity {
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testForkUnit_Euler_burnForBaseDAI01() public {
        console.log("does not burnForBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.burnForBase(alice, 0, uint128(MAX));
    }

    function testForkUnit_Euler_burnForBaseDAI02() public {
        console.log("burns for only base (asset)");

        // using a value that we assume will be below maxSharesOut and maxFYTokenOut, and will allow for trading to base
        uint256 lpTokensToBurn = 1000 * 10**asset.decimals(); // using the asset decimals, since they match the pool

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);
        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        // estimate how many shares and fyToken we will get back from burn
        uint256 sharesOut = (lpTokensToBurn * sharesReservesBefore) / pool.totalSupply();
        // fyTokenOut = lpTokensBurned * realFyTokenReserves / totalSupply
        uint256 fyTokenOut = (lpTokensToBurn * (fyTokenReservesBefore - pool.totalSupply())) / pool.totalSupply();

        // estimate how much shares (and base) we can trade fyToken for, using the new pool state
        uint256 fyTokenOutToShares = YieldMath.sharesOutForFYTokenIn(
            (sharesReservesBefore - sharesOut).u128(),
            (fyTokenReservesBefore - fyTokenOut).u128(),
            fyTokenOut.u128(),
            pool.maturity() - uint32(block.timestamp),
            pool.ts(),
            pool.g2(),
            pool.getC(),
            pool.mu()
        );
        uint256 totalSharesOut = sharesOut + fyTokenOutToShares;
        uint256 expectedAssetsOut = pool.unwrapPreview(totalSharesOut);

        // burnForBase
        vm.startPrank(alice);
        pool.transfer(address(pool), lpTokensToBurn);
        pool.burnForBase(alice, 0, uint128(MAX));

        // check user balances
        assertEq(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut);
        assertEq(fyTokenBalBefore, fyToken.balanceOf(alice));
        assertEq(poolBalBefore - pool.balanceOf(alice), lpTokensToBurn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesBefore - sharesReservesAfter, totalSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, lpTokensToBurn);
    }
}
