// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

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
//    The only difference is they are setup on the PoolYearnVault contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";
import {CastU256U128} from  "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";


import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";
import {ZeroState, ZeroStateParams} from "./shared/ZeroState.sol";

abstract contract ZeroStateYearnDai is ZeroState {
        constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "YearnVault")) {}

}

abstract contract WithLiquidityYearnVault is ZeroStateYearnDai {
    function setUp() public virtual override {
        super.setUp();

        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));
        vm.prank(alice);
        pool.init(alice, bob, 0, MAX);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;

        // Skew the balances without using trading functions
        fyToken.mint(address(pool), additionalFYToken);

        pool.sync();
    }
}

contract Mint__ZeroStateYearnVault is ZeroStateYearnDai {
    function testUnit_YearnVault_mint1() public {
        console.log("adds initial liquidity");

        vm.prank(bob);
        uint256 baseIn = pool.unwrapPreview(INITIAL_YVDAI);
        asset.mint(address(pool), baseIn);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            alice,
            bob,
            address(0),
            int256(-1 * int256(baseIn)),
            int256(0),
            int256(INITIAL_YVDAI)
        );

        vm.prank(alice);
        pool.init(bob, bob, 0, MAX);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);

        require(pool.balanceOf(bob) == INITIAL_YVDAI);
        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_mint2() public {
        console.log("adds liquidity with zero fyToken");
        shares.mint(address(pool), INITIAL_YVDAI);

        vm.startPrank(alice);

        pool.init(address(0), address(0), 0, MAX);

        // After initializing, donate shares and sync to simulate having reached zero fyToken through trading
        shares.mint(address(pool), INITIAL_YVDAI);
        pool.sync();

        shares.mint(address(pool), INITIAL_YVDAI);
        pool.mint(bob, bob, 0, MAX);


        require(pool.balanceOf(bob) == INITIAL_YVDAI / 2);
        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    // Test intentionally ommitted.
    // function testUnit_YearnVault_mint3() public {
    //     console.log("syncs balances after donations");
}

contract Mint__WithLiquidityYearnVault is WithLiquidityYearnVault {
    function testUnit_YearnVault_mint4() public {
        console.log("mints liquidity tokens, returning shares surplus converted to asset");
        uint256 bobAssetBefore = asset.balanceOf(bob);
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
        require(shares.balanceOf(bob) == bobSharesInitialBalance);
        require(asset.balanceOf(bob) == bobAssetBefore + YVTokenMock(address(shares)).pricePerShare()); // 1wad converted

        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();

        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

}

contract Burn__WithLiquidityYearnVault is WithLiquidityYearnVault {
    function testUnit_YearnVault_burn1() public {
        console.log("burns liquidity tokens");
        uint256 bobAssetBefore = asset.balanceOf(address(bob));
        uint256 sharesBalance = shares.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

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

        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(shares.balanceOf(bob) == bobSharesInitialBalance);
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}

abstract contract WithExtraFYTokenYearnVault is WithLiquidityYearnVault {
    using Exp64x64 for uint128;
    using Math64x64 for int128;
    using Math64x64 for int256;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(this), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(this), 0);
    }
}

abstract contract OnceMature is WithExtraFYTokenYearnVault {
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

contract TradeDAI__ZeroStateYearnVault is WithLiquidityYearnVault {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_YearnVault_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (YVTokenMock(address(shares)).pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        fyToken.mint(address(pool), fyTokenIn);
        uint256 expectedSharesOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            virtFYTokenBal,
            uint128(fyTokenIn),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );
        uint256 expectedBaseOut = pool.unwrapPreview(expectedSharesOut);
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, int256(expectedBaseOut), -int256(fyTokenIn));
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 999941268862289926, 340282366920938463463374607431768211455)
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_YearnVault_tradeDAI03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_YearnVault_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (,uint104 fyTokenBalBefore,,) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);
        uint128 sharesOut = uint128(WAD);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (YVTokenMock(address(shares)).pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            virtFYTokenBal,
            sharesOut,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, bob, bob, int256(int128(assetsOut)), -int256(expectedFYTokenIn));
        vm.prank(bob);
        pool.buyBase(bob, uint128(assetsOut), type(uint128).max);

        (, uint104 fyTokenBal,,) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + assetsOut);

        almostEqual(fyTokenIn, expectedFYTokenIn, sharesOut / 1000000);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter,,) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI05() public {
        console.log("does not buy base beyond slippage");
        uint128 sharesOut = 1e18;
        uint128 assetsOut = pool.unwrapPreview(1e18).u128();
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100063608132507117, 0)
        );
        pool.buyBase(bob, assetsOut, 0);
    }

    function testUnit_YearnVault_tradeDAI06() public {
        console.log("buys base and retrieves change");
        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);
        uint256 userFYTokenBefore = fyToken.balanceOf(alice);
        uint128 sharesOut = uint128(WAD);
        uint128 assetsOut = pool.unwrapPreview(sharesOut).u128();

        fyToken.mint(address(pool), initialFYTokens);

        vm.startPrank(alice);
        pool.buyBase(bob, assetsOut, uint128(MAX));
        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + assetsOut);

        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > userFYTokenBefore);
    }
}

contract TradeDAI__WithExtraFYTokenYearnVault is WithExtraFYTokenYearnVault {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_YearnVault_tradeDAI07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint256 aliceBeginningSharesBal = shares.balanceOf(alice);
        uint128 sharesIn = uint128(WAD);
        uint128 assetsIn = pool.unwrapPreview(uint256(sharesIn)).u128();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (YVTokenMock(address(shares)).pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer shares for sale to the pool
        asset.mint(address(pool), assetsIn);

        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            virtFYTokenBal,
            sharesIn,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(assetsIn), int256(expectedFYTokenOut));

        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(fyTokenOut == expectedFYTokenOut);
        (uint104 sharesBal, uint104 fyTokenBal,,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 sharesIn = uint128(WAD);
        uint128 baseIn = pool.unwrapPreview(sharesIn).u128();
        asset.mint(address(pool), baseIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100059306836277437, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_YearnVault_tradeDAI09() public {
        console.log("donates fyToken and sells base");
        uint128 sharesIn = uint128(WAD);
        uint128 assetsIn = pool.unwrapPreview(sharesIn).u128();
        uint128 fyTokenDonation = uint128(WAD);

        fyToken.mint(address(pool), fyTokenDonation);
        asset.mint(address(pool), assetsIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter,,) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_YearnVault_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesCachedBefore,,,) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (YVTokenMock(address(shares)).pricePerShare().fromUInt()).div(uint256(1e18).fromUInt());

        uint128 assetsIn = pool.unwrapPreview(initialShares).u128();
        // Transfer shares for sale to the pool
        asset.mint(address(pool), assetsIn);

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
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn);

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(int256(expectedAssetsIn)), int256(int128(fyTokenOut)));

        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent,,) = pool.getCache();

        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;
        uint256 sharesChange = pool.getSharesBalance() - sharesCachedCurrent;

        require(
            fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut,
            "'User2' wallet should have 1 fyToken token"
        );

        almostEqual(sharesIn, expectedSharesIn, sharesIn / 1000000);
        require(sharesCachedCurrent + sharesChange == pool.getSharesBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(WAD);

        shares.mint(address(pool), initialShares);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 999946996518196437, 0)
        );
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    function testUnit_YearnVault_tradeDAI12() public {
        console.log("donates base and buys fyToken");
        uint256 sharesBalances = pool.getSharesBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (uint104 sharesCachedBefore,,,) = pool.getCache();

        uint128 fyTokenOut = uint128(WAD);
        uint128 baseDonation = pool.unwrapPreview(uint128(WAD)).u128();

        asset.mint(address(pool), pool.unwrapPreview(initialShares).u128() + baseDonation);

        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent,,) = pool.getCache();
        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;

        require(sharesCachedCurrent == sharesBalances + sharesIn);
        require(fyTokenCachedCurrent == fyTokenBalances - fyTokenOut);
    }
}

contract TradeDAI__OnceMatureYearnVault is OnceMature {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_YearnVault_tradeDAI13() internal {
        console.log("doesn't allow sellBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBase(alice, 0);
    }

    function testUnit_YearnVault_tradeDAI14() internal {
        console.log("doesn't allow buyBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBase(alice, uint128(WAD), uint128(MAX));
    }

    function testUnit_YearnVault_tradeDAI15() internal {
        console.log("doesn't allow sellFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYToken(alice, 0);
    }

    function testUnit_YearnVault_tradeDAI16() internal {
        console.log("doesn't allow buyFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYToken(alice, uint128(WAD), uint128(MAX));
    }
}
