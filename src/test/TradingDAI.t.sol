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

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {WithLiquidity} from "./MintBurn.t.sol";
import {FYTokenMock} from "./mocks/FYTokenMock.sol";
import {YVTokenMock} from "./mocks/YVTokenMock.sol";

abstract contract WithExtraFYToken is WithLiquidity {
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

abstract contract OnceMature is WithExtraFYToken {
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

contract TradeDAI__WithLiquidity is WithLiquidity {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

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

    function testUnit_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 909037517147536297, 340282366920938463463374607431768211455)
        );
        pool.sellFYToken(bob, type(uint128).max);
    }

    function testUnit_tradeDAI03() public {
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

    function testUnit_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (, , uint104 fyTokenBalBefore,) = pool.getCache();

        uint256 userBaseBefore = base.balanceOf(bob);

        uint128 baseOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

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

    function testUnit_tradeDAI05() public {
        console.log("does not buy base beyond slippage");
        uint128 baseOut = 1e18;
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100063608132507117, 0)
        );
        pool.buyBase(bob, baseOut, 0);
    }

    function testUnit_tradeDAI06() public {
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

contract TradeDAI__WithExtraFYToken is WithExtraFYToken {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_tradeDAI07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint256 aliceBeginningBaseBal = base.balanceOf(alice);
        uint128 baseIn = uint128(WAD);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

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

        // uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        // require(aliceBeginningBaseBal == base.balanceOf(alice), "'From' wallet should have not increase base tokens");
        // require(fyTokenOut == expectedFYTokenOut);
        // (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        // require(baseBal == pool.getBaseBalance());
        // require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 baseIn = uint128(WAD);
        base.mint(address(pool), baseIn);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100059306836277437, 340282366920938463463374607431768211455)
        );
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeDAI09() public {
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

    function testUnit_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (, uint104 baseCachedBefore,,) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (base.convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

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

    function testUnit_tradeDAI11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(WAD);

        base.mint(address(pool), initialBase);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 909042724107451307, 0)
        );
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    function testUnit_tradeDAI12() public {
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

contract TradeDAI__OnceMature is OnceMature {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_tradeDAI13() internal {
        console.log("doesn't allow sellBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellBase(alice, 0);
    }

    function testUnit_tradeDAI14() internal {
        console.log("doesn't allow buyBase");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBasePreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyBase(alice, uint128(WAD), uint128(MAX));
    }

    function testUnit_tradeDAI15() internal {
        console.log("doesn't allow sellFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.sellFYToken(alice, 0);
    }

    function testUnit_tradeDAI16() internal {
        console.log("doesn't allow buyFYToken");
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYTokenPreview(uint128(WAD));
        vm.expectRevert(bytes("Pool: Too late"));
        pool.buyFYToken(alice, uint128(WAD), uint128(MAX));
    }
}
