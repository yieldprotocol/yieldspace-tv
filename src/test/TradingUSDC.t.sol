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
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import {almostEqual, setPrice} from "./shared/Utils.sol";
import {IERC4626Mock} from "./mocks/ERC4626TokenMock.sol";
import "./shared/Constants.sol";
// import {ERC4626TokenMock} from "./mocks/ERC4626TokenMock.sol";
import {ZeroState, ZeroStateParams} from "./shared/ZeroState.sol";

abstract contract ZeroStateUSDC is ZeroState {
    constructor() ZeroState(ZeroStateParams("USDC", "USDC", 6, "4626")) {}
}

abstract contract WithLiquidity is ZeroStateUSDC {
    function setUp() public virtual override {
        super.setUp();
        shares.mint(address(pool), initialShares);
        vm.prank(alice);
        pool.init(address(0), address(0), 0, MAX);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        fyToken.mint(address(pool), initialFYTokens);
        pool.sync();
    }
}

abstract contract WithExtraFYTokenUSDC is WithLiquidity {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(this), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(this), 0);
    }
}

contract TradeUSDC__WithLiquidity is WithLiquidity {
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
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 999135, 340282366920938463463374607431768211455)
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

    function testUnit_tradeUSDC05() public {
        console.log("does not buy base beyond slippage");
        uint128 sharesOut = 1e6;
        uint128 baseOut = pool.unwrapPreview(sharesOut).u128();
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100949, 0));
        pool.buyBase(bob, baseOut, 0);
    }

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
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100837, 340282366920938463463374607431768211455)
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

    function testUnit_tradeUSDC11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(1e6);

        asset.mint(address(pool), pool.wrapPreview(initialShares));
        vm.expectRevert(abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 999240, 0));
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

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
