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
//    The only difference is they are setup and based on the PoolYearnVault contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~


import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {ZeroStateYearnVaultDai} from "./shared/ZeroStateYearnVault.sol";

abstract contract WithLiquidityYearnVault is ZeroStateYearnVaultDai {
    function setUp() public virtual override {
        super.setUp();
        base.mint(address(pool), INITIAL_BASE * 10**(base.decimals()));

        vm.prank(alice);
        pool.init(alice, bob, 0, MAX);
        base.setPrice((cNumerator * (10**base.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_BASE * 10**(base.decimals())) / 9;

        // Skew the balances without using trading functions
        fyToken.mint(address(pool), additionalFYToken);

        pool.sync();
    }
}

contract Mint__ZeroStateYearnVault is ZeroStateYearnVaultDai {
    function testUnit_YearnVault_mint1() public {
        console.log("adds initial liquidity");

        vm.startPrank(bob);
        base.transfer(address(pool), INITIAL_YVDAI);

        vm.expectEmit(true, true, true, true);
        emit Liquidity(
            maturity,
            bob,
            bob,
            address(0),
            int256(-1 * int256(INITIAL_YVDAI)),
            int256(0),
            int256(INITIAL_YVDAI)
        );

        pool.init(bob, bob, 0, MAX);
        base.setPrice((cNumerator * (10**base.decimals())) / cDenominator);

        require(pool.balanceOf(bob) == INITIAL_YVDAI);
        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_mint2() public {
        console.log("adds liquidity with zero fyToken");
        base.mint(address(pool), INITIAL_YVDAI);

        vm.startPrank(alice);

        pool.init(address(0), address(0), 0, MAX);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        base.mint(address(pool), INITIAL_YVDAI);
        pool.sync();

        base.mint(address(pool), INITIAL_YVDAI);
        pool.mint(bob, bob, 0, MAX);


        require(pool.balanceOf(bob) == INITIAL_YVDAI / 2);
        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_mint3() public {
        console.log("syncs balances after donations");

        base.mint(address(pool), INITIAL_YVDAI);
        fyToken.mint(address(pool), INITIAL_YVDAI / 9);

        vm.expectEmit(false, false, false, true);
        emit Sync(uint104(INITIAL_YVDAI), uint104(INITIAL_YVDAI / 9), 0);

        vm.prank(alice);
        pool.sync();

        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
}

contract Mint__WithLiquidityYearnVault is WithLiquidityYearnVault {
    function testUnit_YearnVault_mint4() public {
        console.log("mints liquidity tokens, returning base surplus");
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e18;
        uint256 expectedBaseIn = (base.balanceOf(address(pool)) * expectedMint) / pool.totalSupply();

        uint256 poolTokensBefore = pool.balanceOf(bob);

        base.mint(address(pool), expectedBaseIn + 1e18); // send an extra wad of base
        fyToken.mint(address(pool), fyTokenIn);

        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(base.balanceOf(bob), WAD + bobBaseInitialBalance, fyTokenIn / 10000);

        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();

        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

}

contract Burn__WithLiquidityYearnVault is WithLiquidityYearnVault {
    function testUnit_YearnVault_burn1() public {
        console.log("burns liquidity tokens");
        uint256 baseBalance = base.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        address charlie = address(3);

        uint256 expectedBaseOut = (lpTokensIn * baseBalance) / poolSup;
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
            int256(expectedBaseOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);


        uint256 baseOut = baseBalance - base.balanceOf(address(pool));
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(baseOut, expectedBaseOut, baseOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(base.balanceOf(bob) - bobBaseInitialBalance == baseOut);
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

    function testUnit_YearnVault_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.getPricePerFullShare().fromUInt()).div(uint256(1e18).fromUInt());

        fyToken.mint(address(pool), fyTokenIn);
        uint256 expectedBaseOut = YieldMath.sharesOutForFYTokenIn(
            sharesReserves,
            virtFYTokenBal,
            uint128(fyTokenIn),
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, int256(expectedBaseOut), -int256(fyTokenIn));
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 909037517147536297, 340282366920938463463374607431768211455)
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    function testUnit_YearnVault_tradeDAI03() public {
        console.log("donates base and sells fyToken");

        uint256 baseDonation = WAD;
        uint256 fyTokenIn = WAD;

        base.mint(address(pool), baseDonation);
        fyToken.mint(address(pool), fyTokenIn);

        vm.prank(bob);
        pool.sellFYToken(bob, 0);

        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (, , uint104 fyTokenBalBefore,) = pool.getCache();

        uint256 userBaseBefore = base.balanceOf(bob);

        uint128 baseOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.getPricePerFullShare().fromUInt()).div(uint256(1e18).fromUInt());

        fyToken.mint(address(pool), initialFYTokens); // send some tokens to the pool

        uint256 expectedFYTokenIn = YieldMath.fyTokenInForSharesOut(
            sharesReserves,
            virtFYTokenBal,
            baseOut,
            maturity - uint32(block.timestamp),
            k,
            g2,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, bob, bob, int256(int128(baseOut)), -int256(expectedFYTokenIn));
        vm.prank(bob);
        pool.buyBase(bob, uint128(baseOut), type(uint128).max);

        (, , uint104 fyTokenBal,) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(base.balanceOf(bob) == userBaseBefore + baseOut);

        almostEqual(fyTokenIn, expectedFYTokenIn, baseOut / 1000000);

        (, uint104 baseBalAfter, uint104 fyTokenBalAfter,) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI05() public {
        console.log("does not buy base beyond slippage");
        uint128 baseOut = 1e18;
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100063608132507117, 0)
        );
        pool.buyBase(bob, baseOut, 0);
    }

    function testUnit_YearnVault_tradeDAI06() public {
        console.log("buys base and retrieves change");
        uint256 userBaseBefore = base.balanceOf(bob);
        uint256 userFYTokenBefore = fyToken.balanceOf(alice);
        uint128 baseOut = uint128(WAD);

        fyToken.mint(address(pool), initialFYTokens);

        vm.startPrank(alice);
        pool.buyBase(bob, baseOut, uint128(MAX));
        require(base.balanceOf(bob) == userBaseBefore + baseOut);

        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal != pool.getFYTokenBalance());

        pool.retrieveFYToken(alice);

        require(fyToken.balanceOf(alice) > userFYTokenBefore);
    }
}

contract TradeDAI__WithExtraFYTokenYearnVault is WithExtraFYTokenYearnVault {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_YearnVault_tradeDAI07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint256 aliceBeginningBaseBal = base.balanceOf(alice);
        uint128 baseIn = uint128(WAD);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.getPricePerFullShare().fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer base for sale to the pool
        base.mint(address(pool), baseIn);

        uint256 expectedFYTokenOut = YieldMath.fyTokenOutForSharesIn(
            sharesReserves,
            virtFYTokenBal,
            baseIn,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(baseIn), int256(expectedFYTokenOut));

        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(aliceBeginningBaseBal == base.balanceOf(alice), "'From' wallet should have not increase base tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 baseIn = uint128(WAD);
        base.mint(address(pool), baseIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100059306836277437, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_YearnVault_tradeDAI09() public {
        console.log("donates fyToken and sells base");
        uint128 baseIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        fyToken.mint(address(pool), fyTokenDonation);
        base.mint(address(pool), baseIn);

        vm.prank(alice);
        pool.sellBase(bob, 0);

        (, uint104 baseBalAfter, uint104 fyTokenBalAfter,) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (, uint104 baseCachedBefore,,) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.getPricePerFullShare().fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer base for sale to the pool
        base.mint(address(pool), initialBase);

        uint256 expectedBaseIn = YieldMath.sharesInForFYTokenOut(
            sharesReserves,
            virtFYTokenBal,
            fyTokenOut,
            maturity - uint32(block.timestamp),
            k,
            g1,
            c_,
            mu
        );

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(int256(expectedBaseIn)), int256(int128(fyTokenOut)));

        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (, uint104 baseCachedCurrent, uint104 fyTokenCachedCurrent,) = pool.getCache();

        uint256 baseIn = baseCachedCurrent - baseCachedBefore;
        uint256 baseChange = pool.getBaseBalance() - baseCachedCurrent;

        require(
            fyToken.balanceOf(bob) == userFYTokenBefore + fyTokenOut,
            "'User2' wallet should have 1 fyToken token"
        );

        almostEqual(baseIn, expectedBaseIn, baseIn / 1000000);
        require(baseCachedCurrent + baseChange == pool.getBaseBalance());
        require(fyTokenCachedCurrent == pool.getFYTokenBalance());
    }

    function testUnit_YearnVault_tradeDAI11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(WAD);

        base.mint(address(pool), initialBase);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 909042724107451307, 0)
        );
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    function testUnit_YearnVault_tradeDAI12() public {
        console.log("donates base and buys fyToken");
        uint256 baseBalances = pool.getBaseBalance();
        uint256 fyTokenBalances = pool.getFYTokenBalance();
        (, uint104 baseCachedBefore,,) = pool.getCache();

        uint128 fyTokenOut = uint128(WAD);
        uint128 baseDonation = uint128(WAD);

        base.mint(address(pool), initialBase + baseDonation);

        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (, uint104 baseCachedCurrent, uint104 fyTokenCachedCurrent,) = pool.getCache();
        uint256 baseIn = baseCachedCurrent - baseCachedBefore;

        require(baseCachedCurrent == baseBalances + baseIn);
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
