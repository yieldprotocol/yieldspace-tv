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

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import {almostEqual, setPrice} from "./shared/Utils.sol";
import {IERC4626Mock} from "./mocks/ERC4626TokenMock.sol";
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

        // Donate an additional 30 WAD fyToken to pool.
        uint256 additionalFYToken = 30 * WAD;
        fyToken.mint(address(pool), additionalFYToken);

        // Alice calls sellFYToken
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
        // Fast forward block timestamp to maturity date.
        vm.warp(pool.maturity());
    }
}

contract TradeDAI__WithLiquidity is WithLiquidity {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Send some fyToken to pool and calculate expectedSharesOut
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

        // Alice calls sellFYToken.
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        // Confirm cached balances are updated properly.
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;

        // Send 1 WAD fyToken to pool.
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellFYToken.selector,
                999785054771931334,
                340282366920938463463374607431768211455
            )
        );
        // Set minRatio to uint128.max and see it get reverted.
        pool.sellFYToken(bob, type(uint128).max);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeDAI03() public {
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    function testUnit_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (, uint104 fyTokenBalBefore, , ) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);

        uint128 sharesOut = uint128(WAD);
        uint128 baseOut = pool.unwrapPreview(sharesOut).u128();

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Send some fyTokens to the pool and see fyTokenIn is as expected.
        fyToken.mint(address(pool), initialFYTokens);

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
        emit Trade(maturity, bob, bob, int256(int128(baseOut)), -int256(expectedFYTokenIn));

        // Bob calls buyBase
        vm.prank(bob);
        pool.buyBase(bob, uint128(baseOut), type(uint128).max);

        // Check cached balances are udpated correctly.
        (, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        almostEqual(fyTokenIn, expectedFYTokenIn, sharesOut / 1000000);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI05() public {
        console.log("does not buy base beyond slippage");
        uint128 sharesOut = 1e18;
        uint128 baseOut = pool.unwrapPreview(sharesOut).u128();

        // Send 1 WAD fyToken to pool.
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100236490669964471, 0));

        // Set maxRatio to 0 and see it revert.
        pool.buyBase(bob, baseOut, 0);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeDAI06() public {
    //     console.log("when buying shares, donating fyToken and extra shares doesn't get absorbed and the shares is unwrapped and sent back");
}

contract TradeDAI__WithExtraFYToken is WithExtraFYToken {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_tradeDAI07() public {
        console.log("sells base for a certain amount of FYTokens");
        uint256 aliceBeginningSharesBal = shares.balanceOf(alice);
        uint128 sharesIn = uint128(WAD);
        uint128 assetsIn = pool.unwrapPreview(sharesIn).u128();

        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Transfer shares for sale to the pool.
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

        // Alice calls sellBase.  Confirm amounts and balances as expected.
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

    function testUnit_tradeDAI08() public {
        console.log("does not sell shares beyond slippage");
        uint128 sharesIn = uint128(WAD);

        // Send 1 WAD shares to the pool.
        shares.mint(address(pool), sharesIn);

        vm.expectRevert(
            abi.encodeWithSelector(
                SlippageDuringSellBase.selector,
                1100213481329461717,
                340282366920938463463374607431768211455
            )
        );
        // Set min acceptable amount to uint128.max and see it revert.
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeDAI09() public {
        console.log("donating fyToken does not affect cache balances when selling base");
        uint128 baseIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        // Donate both fyToken and shares to the pool.
        fyToken.mint(address(pool), fyTokenDonation);
        asset.mint(address(pool), baseIn);

        // Alice calls sellBase. See confirm cached balances.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        (uint104 sharesBalAfter, uint104 fyTokenBalAfter, , ) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (uint104 sharesCachedBefore, , , ) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10**shares.decimals()).fromUInt()).div(
            uint256(1e18).fromUInt()
        );

        // Transfer shares for sale to the pool.
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
        uint256 expectedAssetsIn = pool.unwrapPreview(expectedSharesIn);

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(int256(expectedAssetsIn)), int256(int128(fyTokenOut)));

        // Alice calls buyFYToken.  Confirm caches and user balances.  Confirm sharesIn is as expected.
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

    function testUnit_tradeDAI11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(WAD);

        // Send some shares to the pool.
        shares.mint(address(pool), initialShares);
        vm.expectRevert(abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 999805963634541415, 0));

        // Set max amount out to 0 and watch it revert.
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    // This test intentionally removed. Donating no longer affects reserve balances because extra shares are unwrapped
    // and returned in some cases, extra base is wrapped in other cases, and donating no longer affects reserves.
    // function testUnit_tradeDAI12() public {
    //     console.log("donating fyToken and extra shares doesn't get absorbed into the cache when buying fyTokens");
}

// These tests ensure none of the trading functions work once the pool is matured.
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
