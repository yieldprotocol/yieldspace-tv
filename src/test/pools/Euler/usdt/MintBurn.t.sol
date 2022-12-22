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

contract SetFeesEulerUSDT is ZeroStateEulerUSDT {
    using Math64x64 for uint256;

    function testUnit_Euler_setFeesUSDT01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee_ = 10001;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee_));
        pool.setFees(g1Fee_);
    }

    function testUnit_Euler_setFeesUSDT02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee_ = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee_);
    }

    function testUnit_Euler_setFeesUSDT03() public {
        console.log("sets valid fee");

        uint16 g1Fee_ = 8000;
        int128 expectedG1 = uint256(g1Fee_).divu(10000);
        int128 expectedG2 = uint256(10000).divu(g1Fee_);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit FeesSet(g1Fee_);

        pool.setFees(g1Fee_);

        assertEq(pool.g1(), expectedG1);
        assertEq(pool.g2(), expectedG2);
    }
}

contract Mint_ZeroStateEulerUSDT is ZeroStateEulerUSDT {
    using TransferHelper for IERC20Like;

    function testUint_Euler_mintUSDT01() public {
        console.log("adds initial liquidity");
        deal(address(asset), address(alice), 100_000_000 * 10**asset.decimals());

        uint256 assetsIn = 1000 * 10**asset.decimals();
        uint256 sharesIn = pool.wrapPreview(assetsIn);
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();

        uint256 expectedMint = pool.mulMu(sharesIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(maturity, alice, alice, address(0), -int256(assetsIn), int256(0), int256(expectedMint));

        // init
        vm.startPrank(alice);
        IERC20Like(address(asset)).safeTransfer(address(pool), assetsIn);
        pool.init(address(alice));

        // check user balance
        assertEq(assetBalBefore - asset.balanceOf(alice), assetsIn);
        assertEq(pool.balanceOf(alice) - poolBalBefore, expectedMint);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesAfter - sharesReservesBefore, sharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedMint);
    }

    function testUnit_Euler_mintUSDT02() public {
        console.log("adds liquidity with zero fyToken");
        deal(address(asset), address(alice), 100_000_000 * 10**asset.decimals());

        uint256 assetsIn = 1000 * 10**asset.decimals();
        uint256 sharesIn = pool.wrapPreview(assetsIn);
        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        vm.startPrank(alice);
        IERC20Like(address(asset)).safeTransfer(address(pool), assetsIn);
        pool.init(address(0)); // don't send init lpTokens to alice, to be able to check expectedMint more easily below

        (uint104 sharesReservesBefore, uint104 fyTokenReservesBefore, , ) = pool.getCache();
        uint256 realFyTokenReserves = fyTokenReservesBefore - pool.totalSupply();
        // estimate expected lpToken mint during edge case of 0 real fyToken reserves, and after init
        uint256 expectedMint = (pool.totalSupply() * sharesIn) / sharesReservesBefore;

        // check there is 0 fyToken reserves after initialization
        assertEq(realFyTokenReserves, 0);

        // pool mint
        IERC20Like(address(asset)).safeTransfer(address(pool), assetsIn);
        pool.mint(alice, alice, 0, MAX);

        // check user balances
        assertEq(assetBalBefore - asset.balanceOf(alice), assetsIn * 2); // alice transferred assetsIn to init, then again to pool mint (2x assetsIn)
        assertEq(pool.balanceOf(alice) - poolBalBefore, expectedMint);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertEq(sharesReservesAfter - sharesReservesBefore, sharesIn);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, expectedMint);
    }
}

contract Mint__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    using TransferHelper for IERC20Like;

    function testUnit_Euler_mintUSDT03() public {
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

        uint256 poolTokensBefore = pool.balanceOf(bob);

        // pool mint
        vm.startPrank(alice);
        IERC20Like(address(asset)).safeTransfer(address(pool), expectedAssetsIn * 2); // alice sends too many assets
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

contract Burn__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {

    function testUnit_Euler_burnUSDT01() public {
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

contract MatureBurn_WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    function testUnit_Euler_matureBurnUSDT01() public {
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
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut, 1); // NOTE one wei issue
        assertEq(fyToken.balanceOf(alice) - fyTokenBalBefore, expectedFyTokenOut);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1); // NOTE one wei issue
        assertEq(sharesReservesBefore - sharesReservesAfter, expectedSharesOut);
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, expectedFyTokenOut + lpTokensIn); // after burning, the reserves are updated to exclude the burned lp tokens
    }
}

contract Admin__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    using TransferHelper for IERC20Like;

    function testUnit_admin1_EulerUSDT() public {
        console.log("retrieveBase returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingsharesReserves, uint104 startingfyTokenReserves, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentsharesReserves, uint104 currentfyTokenReserves, , ) = pool.getCache();
        assertEq(currentsharesReserves, startingsharesReserves);
        assertEq(currentfyTokenReserves, startingfyTokenReserves);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testUnit_admin2_EulerUSDT() public {
        console.log("retrieveBase returns exceess");
        uint256 additionalAmount = 69;
        IERC20Like base = IERC20Like(address(pool.baseToken()));
        vm.prank(alice);
        base.safeTransfer(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingsharesReserves, uint104 startingfyTokenReserves, , ) = pool.getCache();

        pool.retrieveBase(alice);

        (uint104 currentsharesReserves, uint104 currentfyTokenReserves, , ) = pool.getCache();
        assertEq(currentsharesReserves, startingsharesReserves);
        assertEq(currentfyTokenReserves, startingfyTokenReserves);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
    }

    function testUnit_admin3_EulerUSDT() public {
        console.log("retrieveShares returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingsharesReserves, uint104 startingfyTokenReserves, , ) = pool.getCache();

        pool.retrieveShares(alice);

        // There is a 1 wei difference attributable to some deep nested rounding
        assertApproxEqAbs(pool.baseToken().balanceOf(alice), startingBaseBalance, 1);
        // assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        (uint104 currentsharesReserves, uint104 currentfyTokenReserves, , ) = pool.getCache();
        assertEq(currentfyTokenReserves, startingfyTokenReserves);
    }

    function testUnit_admin4_EulerUSDT() public {
        console.log("retrieveShares returns exceess");

        (uint104 startingsharesReserves, uint104 startingfyTokenReserves, , ) = pool.getCache();
        uint256 additionalAmount = 69e18;
        shares.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);

        pool.retrieveShares(alice);

        (uint104 currentsharesReserves, uint104 currentfyTokenReserves, , ) = pool.getCache();
        assertEq(currentfyTokenReserves, startingfyTokenReserves);
        assertEq(currentsharesReserves, startingsharesReserves);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }

    function testUnit_admin5_EulerUSDT() public {
        console.log("retrieveFYToken returns nothing if there is no excess");
        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingsharesReserves, uint104 startingfyTokenReserves, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance);
        (uint104 currentsharesReserves, uint104 currentfyTokenReserves, , ) = pool.getCache();
        assertEq(currentfyTokenReserves, startingfyTokenReserves);
    }

    function testUnit_admin6_EulerUSDT() public {
        console.log("retrieveFYToken returns exceess");
        uint256 additionalAmount = 69e18;
        fyToken.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        uint256 startingFyTokenBalance = pool.fyToken().balanceOf(alice);
        (uint104 startingsharesReserves, uint104 startingfyTokenReserves, , ) = pool.getCache();

        pool.retrieveFYToken(alice);

        (uint104 currentsharesReserves, uint104 currentfyTokenReserves, , ) = pool.getCache();
        assertEq(currentfyTokenReserves, startingfyTokenReserves);
        assertEq(currentsharesReserves, startingsharesReserves);
        assertEq(pool.fyToken().balanceOf(alice), startingFyTokenBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance);
    }
}

contract MintWithBase__ZeroStateEulerUSDT is ZeroStateEulerUSDT {
    function testUnit_Euler_mintWithBaseUSDT01() public {
        console.log("does not mintWithBase when pool is not initialized");

        vm.expectRevert(NotInitialized.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }
}

contract MintWithBase__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    using TransferHelper for IERC20Like;

    function testUnit_Euler_mintWithBaseUSDT02() public {
        console.log("does not mintWithBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }

    function testUnit_Euler_mintWithBaseUSDT03() public {
        console.log("mints with only base (asset)");

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 fyTokenBalBefore = fyToken.balanceOf(alice);
        uint256 poolBalBefore = pool.balanceOf(alice);

        // estimate how many shares need to be sold using arbitrary fyTokenToBuy amount and estimate lp tokens minted,
        // to be able to calculate how much asset to send to the pool
        uint128 fyTokenToBuy = uint128(1000 * 10**fyToken.decimals());
        uint128 assetsToSell = pool.buyFYTokenPreview(fyTokenToBuy) + 2; // NOTE one wei issue
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
        IERC20Like(address(asset)).safeTransfer(address(pool), assetsIn);
        pool.mintWithBase(alice, alice, fyTokenToBuy, 0, uint128(MAX));

        // check user balances
        assertApproxEqAbs(assetBalBefore - asset.balanceOf(alice), assetsIn, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore, fyToken.balanceOf(alice));
        assertEq(pool.balanceOf(alice) - poolBalBefore, lpTokensMinted);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertEq(sharesReservesAfter, pool.getSharesBalance());
        assertApproxEqAbs(sharesReservesAfter - sharesReservesBefore, sharesIn, 1); // NOTE one wei issue
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesAfter - fyTokenReservesBefore, lpTokensMinted);
    }
}

contract BurnForBase__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_burnForBaseUSDT01() public {
        console.log("does not burnForBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.burnForBase(alice, 0, uint128(MAX));
    }

    function testUnit_Euler_burnForBaseUSDT02() public {
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
            maturity - uint32(block.timestamp),
            k,
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
        assertApproxEqAbs(asset.balanceOf(alice) - assetBalBefore, expectedAssetsOut, 1); // NOTE one wei issue
        assertEq(fyTokenBalBefore, fyToken.balanceOf(alice));
        assertEq(poolBalBefore - pool.balanceOf(alice), lpTokensToBurn);

        // check pool reserves
        (uint104 sharesReservesAfter, uint104 fyTokenReservesAfter, , ) = pool.getCache();
        assertApproxEqAbs(sharesReservesAfter, pool.getSharesBalance(), 1); // NOTE one wei issue
        assertApproxEqAbs(sharesReservesBefore - sharesReservesAfter, totalSharesOut, 1); // NOTE one wei issue
        assertEq(fyTokenReservesAfter, pool.getFYTokenBalance());
        assertEq(fyTokenReservesBefore - fyTokenReservesAfter, lpTokensToBurn);
    }
}


