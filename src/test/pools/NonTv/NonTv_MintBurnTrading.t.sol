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
//    These tests are exactly copy and pasted from the MintBurn.t.sol and TradingDAI.t.sol test suites.
//    The only difference is they are setup and based on the PoolNonTv contract instead of the Pool contract
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
import {CastI128U128} from "@yield-protocol/utils-v2/contracts/cast/CastI128U128.sol";

import "../../shared/Utils.sol";
import "../../shared/Constants.sol";
import {YVTokenMock} from "../../mocks/YVTokenMock.sol";
import {ZeroState, ZeroStateParams} from "../../shared/ZeroState.sol";
import {IERC20Like} from "../../../interfaces/IERC20Like.sol";

abstract contract ZeroStateNonTv is ZeroState {
    constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "NonTv")) {}
}

abstract contract WithLiquidityNonTv is ZeroStateNonTv {
    function setUp() public virtual override {
        super.setUp();
        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));
        vm.prank(alice);
        pool.init(alice);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);
    }
}

contract SetFeesNonTv is ZeroStateNonTv {
    using Math64x64 for uint256;

    function testUnit_NonTv_setFees01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee = 10001;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee));
        pool.setFees(g1Fee);
    }

    function testUnit_NonTv_setFees02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee);
    }

    function testUnit_NonTv_setFees03() public {
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

contract Mint__ZeroStateNonTv is ZeroStateNonTv {
    function testUnit_NonTv_mint1() public {
        console.log("adds initial liquidity");

        vm.prank(bob);
        shares.transfer(address(pool), INITIAL_YVDAI);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            alice,
            bob,
            address(0),
            int256(-1 * int256(INITIAL_YVDAI)),
            int256(0),
            int256(INITIAL_YVDAI)
        );

        vm.prank(alice);
        pool.init(bob);

        require(pool.balanceOf(bob) == INITIAL_YVDAI);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_NonTv_mint2() public {
        console.log("adds liquidity with zero fyToken");
        shares.mint(address(pool), INITIAL_YVDAI);

        vm.startPrank(alice);

        pool.init(address(0));

        // After initializing, donate shares and sync to simulate having reached zero fyToken through trading
        shares.mint(address(pool), INITIAL_YVDAI);
        pool.sync();

        shares.mint(address(pool), INITIAL_YVDAI);
        pool.mint(bob, bob, 0, MAX);

        require(pool.balanceOf(bob) == INITIAL_YVDAI / 2);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    // Test intentionally ommitted.
    // function testUnit_NonTv_mint3() public {
    //     console.log("syncs balances after donations");
}

contract Mint__WithLiquidityNonTv is WithLiquidityNonTv {
    function testUnit_NonTv_mint4() public {
        console.log("mints liquidity tokens, returning shares surplus");
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e18;
        uint256 expectedSharesIn = (shares.balanceOf(address(pool)) * expectedMint) / pool.totalSupply();

        uint256 poolTokensBefore = pool.balanceOf(bob);

        shares.mint(address(pool), expectedSharesIn + 1e18); // send an extra wad of shares
        fyToken.mint(address(pool), fyTokenIn);

        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(shares.balanceOf(bob), WAD + bobSharesInitialBalance, fyTokenIn / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();

        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
}

contract Burn__WithLiquidityNonTv is WithLiquidityNonTv {
    function testUnit_NonTv_burn1() public {
        console.log("burns liquidity tokens");
        uint256 sharesBalance = shares.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        address charlie = address(3);

        uint256 expectedSharesOut = (lpTokensIn * sharesBalance) / poolSup;
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
            int256(expectedSharesOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);

        uint256 sharesOut = sharesBalance - shares.balanceOf(address(pool));
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(sharesOut, expectedSharesOut, sharesOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(shares.balanceOf(bob) - bobSharesInitialBalance == sharesOut);
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}

contract MatureBurn_WithLiquidityNonTv is WithLiquidityNonTv {
    function testUnit_NonTv_matureBurn01() public {
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

abstract contract WithExtraFYTokenNonTv is WithLiquidityNonTv {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(pool), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(this), 0);
    }
}

abstract contract OnceMature is WithExtraFYTokenNonTv {
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

contract TradeDAI__ZeroStateNonTv is WithLiquidityNonTv {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_NonTv_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for shares");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = int128(ONE);

        fyToken.mint(address(pool), fyTokenIn);
        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            virtFYTokenBal,
            uint128(fyTokenIn),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            c_
        );
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, int256(expectedSharesOut), -int256(fyTokenIn));
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_NonTv_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellFYToken.selector,
                999768370574989354,
                340282366920938463463374607431768211455
            )
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_NonTv_tradeDAI03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_NonTv_tradeDAI04() public {
        console.log("buys a certain amount shares for fyToken");
        (, uint104 fyTokenBalBefore, , ) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);

        uint128 sharesOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = int128(ONE);

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            virtFYTokenBal,
            sharesOut,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            c_
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, bob, bob, int256(int128(sharesOut)), -int256(expectedFYTokenIn));
        vm.prank(bob);
        pool.buyBase(bob, uint128(sharesOut), type(uint128).max);

        (, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore + sharesOut);

        almostEqual(fyTokenIn, expectedFYTokenIn, sharesOut / 1000000);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    // Removed
    // function testUnit_NonTv_tradeDAI05() public {

    function testUnit_NonTv_tradeDAI06() public {
        console.log("buys shares and retrieves change");
        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userFYTokenBefore = fyToken.balanceOf(alice);
        uint128 sharesOut = uint128(WAD);

        fyToken.mint(address(pool), initialFYTokens);

        vm.startPrank(alice);
        pool.buyBase(bob, sharesOut, uint128(MAX));
        require(shares.balanceOf(bob) == userSharesBefore + sharesOut);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > userFYTokenBefore);
    }
}

contract TradeDAI__WithExtraFYTokenNonTv is WithExtraFYTokenNonTv {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_NonTv_tradeDAI07() public {
        console.log("sells shares for a certain amount of FYTokens");
        uint256 aliceBeginningSharesBal = shares.balanceOf(alice);
        uint128 sharesIn = uint128(WAD);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = ONE;

        // Transfer shares for sale to the pool
        shares.mint(address(pool), sharesIn);

        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            virtFYTokenBal,
            sharesIn,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            c_
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(sharesIn), int256(expectedFYTokenOut));

        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(
            aliceBeginningSharesBal == shares.balanceOf(alice),
            "'From' wallet should have not increase shares tokens"
        );
        require(fyTokenOut == expectedFYTokenOut);
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_NonTv_tradeDAI08() public {
        console.log("does not sell shares beyond slippage");
        uint128 sharesIn = uint128(WAD);
        shares.mint(address(pool), sharesIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellBase.selector,
                1000209141672476586,
                340282366920938463463374607431768211455
            )
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_NonTv_tradeDAI09() public {
        console.log("donates fyToken and sells shares");
        uint128 sharesIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        fyToken.mint(address(pool), fyTokenDonation);
        shares.mint(address(pool), sharesIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_NonTv_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with shares");
        (uint104 sharesCachedBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = int128(ONE);

        // Transfer shares for sale to the pool
        shares.mint(address(pool), initialShares);

        uint256 expectedSharesIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            virtFYTokenBal,
            fyTokenOut,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            c_
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(int256(expectedSharesIn)), int256(int128(fyTokenOut)));

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
    // function testUnit_NonTv_tradeDAI11() public {

    function testUnit_NonTv_tradeDAI12() public {
        console.log("donates shares and buys fyToken");
        uint256 sharesBalances = pool.getSharesBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (uint104 sharesCachedBefore, , , ) = pool.getCache();

        uint128 fyTokenOut = uint128(WAD);
        uint128 sharesDonation = uint128(WAD);

        shares.mint(address(pool), initialShares + sharesDonation);

        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent, , ) = pool.getCache();
        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;

        require(sharesCachedCurrent == sharesBalances + sharesIn);
        require(fyTokenCachedCurrent == fyTokenBalances - fyTokenOut);
    }

    function testUnit_NonTv_tradeDAI13() public {
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

        assertEq(assetBalAfter - assetBalBefore, expectedAssetOut);
        assertEq(fyTokenBalBefore - fyTokenBalAfter, fyTokenIn);
    }

    function testUnit_NonTv_tradeDAI14() public {
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

    function testUnit_NonTv_tradeDAI15() public {
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

    function testUnit_NonTv_tradeDAI16() public {
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

contract TradeDAI__OnceMatureNonTv is OnceMature {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_NonTv_tradeDAI17() internal {
        console.log("doesn't allow sellBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBase(alice, 0);
    }

    function testUnit_NonTv_tradeDAI18() internal {
        console.log("doesn't allow buyBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBase(alice, uint128(WAD), uint128(MAX));
    }

    function testUnit_NonTv_tradeDAI19() internal {
        console.log("doesn't allow sellFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYToken(alice, 0);
    }

    function testUnit_NonTv_tradeDAI20() internal {
        console.log("doesn't allow buyFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYToken(alice, uint128(WAD), uint128(MAX));
    }
}

contract Admin__WithLiquidityNonTv is WithLiquidityNonTv {
    function testUnit_admin1_NonTv() public {
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

    function testUnit_admin2_NonTv() public {
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

        // "sharesToken" and "baseToken" both point to the same token
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance + additionalAmount);
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount);
    }

    function testUnit_admin3_NonTv() public {
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

    function testUnit_admin4_NonTv() public {
        console.log("retrieveShares returns exceess");

        uint256 additionalAmount = 69e18;
        shares.mint(address(pool), additionalAmount);

        uint256 startingBaseBalance = pool.baseToken().balanceOf(alice);
        uint256 startingSharesBalance = pool.sharesToken().balanceOf(alice);
        (uint104 startingSharesCached, uint104 startingFyTokenCached, , ) = pool.getCache();

        pool.retrieveShares(alice);

        (uint104 currentSharesCached, uint104 currentFyTokenCached, , ) = pool.getCache();
        assertEq(currentFyTokenCached, startingFyTokenCached);
        assertEq(currentSharesCached, startingSharesCached);

        // "sharesToken" and "baseToken" both point to the same token
        assertEq(pool.sharesToken().balanceOf(alice), startingSharesBalance + additionalAmount);
        assertEq(pool.baseToken().balanceOf(alice), startingBaseBalance + additionalAmount);
    }

    function testUnit_admin5_NonTv() public {
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

    function testUnit_admin6_NonTv() public {
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

contract MintWithBase__ZeroStateNonTv is ZeroStateNonTv {
    function testUnit_NonTv_mintWithBase01() public {
        console.log("does not mintWithBase when pool is not initialized");

        vm.expectRevert(NotInitialized.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }
}

contract MintWithBase__WithLiquidityNonTv is WithLiquidityNonTv {
    function testUnit_NonTv_mintWithBase02() public {
        console.log("does not mintWithBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.mintWithBase(alice, alice, 0, 0, uint128(MAX));
    }

    function testUnit_NonTv_mintWithBase03() public {
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

contract BurnForBase__WithLiquidityNonTv is WithLiquidityNonTv {
    using Math64x64 for uint256;
    using CastU256U128 for uint256;
    using CastI128U128 for int128;

    function testUnit_NonTv_burnForBase01() public {
        console.log("does not burnForBase when mature");

        vm.warp(pool.maturity());
        vm.expectRevert(AfterMaturity.selector);
        vm.prank(alice);
        pool.burnForBase(alice, 0, uint128(MAX));
    }

    function testUnit_NonTv_burnForBase02() public {
        console.log("burns for only base (asset)");

        // check if non-tv
        assertEq(pool.getC(), pool.mu());

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
