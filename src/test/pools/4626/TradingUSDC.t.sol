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

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../Math64x64.sol";
import {YieldMath} from "../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import {almostEqual, setPrice} from "../../shared/Utils.sol";
import {IERC4626Mock} from "../../mocks/ERC4626TokenMock.sol";
import "../../shared/Constants.sol";
import {FYTokenMock} from "../../mocks/FYTokenMock.sol";
import "./State.sol";

contract TradeUSDC__WithLiquidity is WithLiquidityUSDC {
    using Math64x64 for uint256;
    using Math64x64 for int128;
    using CastU256U128 for uint256;

    function testUnit_tradeUSDC01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e6;

        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC02() public {
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
    // function testUnit_tradeUSDC03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_tradeUSDC04() public {
        console.log("buys a certain amount base for fyToken");
        (, uint104 fyTokenBalBefore, , ) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);
        uint128 sharesOut = uint128(1000 * 1e6);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e6).fromUInt()
        );

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves * 1e12,
            virtFYTokenBal * 1e12,
            sharesOut * 1e12,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        ) / 1e12;

        vm.prank(bob);
        pool.buyBase(bob, assetsOut, type(uint128).max);

        (, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        almostEqual(fyTokenIn, expectedFYTokenIn, 1);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_tradeUSDC05() public {

    function testUnit_tradeUSDC06() public {
        console.log("buys base and retrieves change");
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 aliceFYTokenBefore = fyToken.balanceOf(alice);
        uint128 sharesOut = uint128(1e6);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        fyToken.mint(address(pool), initialFYTokens);

        vm.prank(alice);
        pool.buyBase(bob, assetsOut, uint128(MAX));
        require(shares.balanceOf(bob) == bobSharesBefore);
        require(asset.balanceOf(bob) == bobAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        vm.prank(alice);
        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > aliceFYTokenBefore);
    }
}

contract TradeUSDC__WithExtraFYToken is WithExtraFYTokenUSDC {
    using Math64x64 for uint256;
    using Math64x64 for int128;

    function testUnit_tradeUSDC07() public {
        uint128 sharesIn = uint128(25000 * 1e6);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint256 userSharesBalanceBefore = shares.balanceOf(alice);
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e6).fromUInt()
        );

        // Transfer shares for sale to the pool
        shares.mint(address(pool), sharesIn);
        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves * 1e12,
            virtFYTokenBal * 1e12,
            sharesIn * 1e12,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        ) / 1e12;

        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(shares.balanceOf(alice) == userSharesBalanceBefore, "'From' wallet should have no shares tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeUSDC08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(1e6);
        uint128 assetsIn = uint128(pool.unwrapPreview(sharesIn));
        asset.mint(address(pool), assetsIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100213, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeUSDC09() public {
        console.log("donating fyToken does not affect cache balances when selling base");
        uint128 baseIn = uint128(1e6);
        uint128 fyTokenDonation = uint128(1e6);

        fyToken.mint(address(pool), fyTokenDonation);
        asset.mint(address(pool), baseIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_tradeUSDC10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesCachedBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(1e6);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e6).fromUInt()
        );

        // Transfer shares for sale to the pool
        asset.mint(address(pool), pool.unwrapPreview(initialShares));

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            virtFYTokenBal,
            fyTokenOut,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();

        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;
        uint256 sharesChange = pool.getSharesBalance() - sharesCachedCurrent;

        require(fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut, "'User2' wallet should have 1 fyToken token");

        almostEqual(sharesIn, expectedSharesIn, sharesIn / 100000);
        require(sharesCachedCurrent + sharesChange == pool.getSharesBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_tradeUSDC11() public {

    function testUnit_tradeUSDC12() public {
        console.log("donates shares and buys fyToken");
        uint256 sharesBalances = pool.getSharesBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (uint104 sharesCachedBefore, , , ) = pool.getCache();

        uint128 fyTokenOut = uint128(1e6);
        uint128 sharesDonation = uint128(1e6);

        shares.mint(address(pool), initialShares + sharesDonation);

        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();
        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;

        require(sharesCachedCurrent == sharesBalances + sharesIn);
        require(fyTokenCachedCurrent == fyTokenBalances - fyTokenOut);
    }
}

contract TradeUSDCPreviews__WithExtraFYToken is WithExtraFYTokenUSDC {
    function testUnit_tradeUSDC13() public {
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

    // getting one wei difference between expected fyToken out
    // causing revert within trade func
    function testUnit_tradeUSDC14() public {
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

    function testUnit_tradeUSDC15() public {
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

    function testUnit_tradeUSDC16() public {
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
