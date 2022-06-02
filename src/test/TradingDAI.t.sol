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
        fyToken.mint(address(this), additionalFYToken);

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

    function testUnit_tradeDAI01() public {
        console.log("sells a certain amount of fyToken for base");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(base)).convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

        // Send some fyToken to pool and calculate expectedBaseOut
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

        // Alice calls sellFYToken.
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        // Confirm cached balances are updated properly.
        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI02() public {
        console.log("does not sell fyToken beyond slippage");
        uint256 fyTokenIn = 1e18;

        // Send 1 WAD fyToken to pool.
        fyToken.mint(address(pool), fyTokenIn);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellFYToken.selector, 909037517972875801, 340282366920938463463374607431768211455));
        // Set minRatio to uint128.max and see it get reverted.
        pool.sellFYToken(bob, type(uint128).max);
    }

    // TODO: Do we still need this test since update is removed?  If so needs to be rewritten.
    // function testUnit_tradeDAI03() public {
    //     console.log("donating base does not affect cache balances when selling fyToken");

    //     uint256 baseDonation = WAD;
    //     uint256 fyTokenIn = WAD;

    //     // Donate base and fyToken to pool.
    //     base.mint(address(pool), baseDonation);
    //     fyToken.mint(address(pool), fyTokenIn);

    //     // Bob calls sellFYToken
    //     vm.prank(bob);
    //     pool.sellFYToken(bob, 0);

    //     // Check cached balances are udpated correctly.
    //     (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
    //     require(baseBal == pool.getBaseBalance() - baseDonation);
    //     require(fyTokenBal == pool.getFYTokenBalance());
    // }

    function testUnit_tradeDAI04() public {
        console.log("buys a certain amount base for fyToken");
        (, , uint104 fyTokenBalBefore,) = pool.getCache();

        uint256 userBaseBefore = base.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);

        uint128 baseOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(base)).convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

        // Send some fyTokens to the pool and see fyTokenIn is as expected.
        fyToken.mint(address(pool), initialFYTokens);

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

        // Bob calls buyBase
        vm.prank(bob);
        pool.buyBase(bob, uint128(baseOut), type(uint128).max);

        // Check cached balances are udpated correctly.
        (, , uint104 fyTokenBal,) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(base.balanceOf(bob) == userBaseBefore);
        require(asset.balanceOf(bob) == userAssetBefore + IERC4626Mock(address(base)).convertToAssets(baseOut));

        almostEqual(fyTokenIn, expectedFYTokenIn, baseOut / 1000000);

        (, uint104 baseBalAfter, uint104 fyTokenBalAfter,) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI05() public {
        console.log("does not buy base beyond slippage");
        uint128 baseOut = 1e18;

        // Send 1 WAD fyToken to pool.
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100063607139041184, 0)
        );

        // Set maxRatio to 0 and see it revert.
        pool.buyBase(bob, baseOut, 0);
    }

    function testUnit_tradeDAI06() public {
        console.log("when buying base, donating fyToken and extra base doesn't get absorbed and the base is unwrapped and sent back");
        // TODO: Not sure this tests is necessary as the dynamics have changed.  Here is what the old test did:
        // console.log("when buying base, donating fyToken and extra base doesn't get absorbed and can be retrieved");
        uint256 aliceBaseBefore = base.balanceOf(alice);
        uint256 bobBaseBefore = base.balanceOf(bob);
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 aliceFYTokenBefore = fyToken.balanceOf(alice);
        uint128 baseOut = uint128(WAD * 10);
        uint128 expectedFYTokenIn = pool.buyBasePreview(baseOut);
        uint128 extraFYToken = uint128(5 * 1e17); // half wad
        uint128 extraBase = uint128(WAD) * 5;


        // Send some fyTokens to the pool.
        fyToken.mint(address(pool), expectedFYTokenIn + extraFYToken);
        base.mint(address(pool), extraBase);

        // Alice call buyBase, check balances are as expected.
        vm.startPrank(alice);
        pool.buyBase(bob, baseOut, uint128(MAX));
        require(base.balanceOf(bob) == bobBaseBefore);
        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance() - extraFYToken);
        require(asset.balanceOf(bob) == bobAssetBefore + IERC4626Mock(address(base)).convertToAssets(baseOut + extraBase));
        pool.retrieveFYToken(alice);
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());

        require(fyToken.balanceOf(alice) == aliceFYTokenBefore + extraFYToken);
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
        int128 c_ = (IERC4626Mock(address(base)).convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer base for sale to the pool.
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

        // Alice calls sellBase.  Confirm amounts and balances as expected.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(aliceBeginningBaseBal == base.balanceOf(alice), "'From' wallet should have not increase base tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (, uint104 baseBal, uint104 fyTokenBal,) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI08() public {
        console.log("does not sell base beyond slippage");
        uint128 baseIn = uint128(WAD);

        // Send 1 WAD base to the pool.
        base.mint(address(pool), baseIn);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100059305930990583, 340282366920938463463374607431768211455)
        );
        // Set min acceptable amount to uint128.max and see it revert.
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeDAI09() public {
        console.log("donating fyToken does not affect cache balances when selling base");
        uint128 baseIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        // Donate both fyToken and base to the pool.
        fyToken.mint(address(pool), fyTokenDonation);
        base.mint(address(pool), baseIn);

        // Alice calls sellBase. See confirm cached balances.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        (, uint104 baseBalAfter, uint104 fyTokenBalAfter,) = pool.getCache();

        require(baseBalAfter == pool.getBaseBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with base");
        (, uint104 baseCachedBefore,,) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(base.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(base)).convertToAssets(10 ** base.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer base for sale to the pool.
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

        // Alice calls buyFYToken.  Confirm caches and user balances.  Confirm baseIn is as expected.
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

        // Send some base to the pool.
        base.mint(address(pool), initialBase);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 909042724853432477, 0)
        );

        // Set max amount out to 0 and watch it revert.
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    function testUnit_tradeDAI12() public {
        console.log("donating fyToken and extra base doesn't get absorbed into the cache when buying fyTokens");
        uint256 baseBalance = pool.getBaseBalance();
        uint256 fyTokenBalance = pool.getFYTokenBalance();
        (, uint104 baseCachedBefore,,) = pool.getCache();

        uint128 fyTokenOut = uint128(WAD * 10);
        uint128 expectedBaseIn = pool.buyFYTokenPreview(fyTokenOut);
        uint128 extraBase = uint128(WAD) * 5;
        uint128 extraFYToken = uint128(5 * 1e17); // half wad

       // Send some base to the pool.
        base.mint(address(pool), expectedBaseIn + extraBase);
        fyToken.mint(address(pool), extraFYToken);
        require(pool.getBaseBalance() == baseBalance + extraBase + expectedBaseIn);

        // Alice does buyFYToken. Confirm caches and balances.
        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));
        require(pool.getBaseBalance() == baseBalance + extraBase + expectedBaseIn);
        (, uint104 baseCachedCurrent, uint104 fyTokenCachedCurrent,) = pool.getCache();
        uint256 baseIn = baseCachedCurrent - baseCachedBefore;
        require(baseCachedCurrent == baseBalance + baseIn);
        require(baseCachedCurrent + extraBase == pool.getBaseBalance());
        require(fyTokenCachedCurrent == fyTokenBalance - fyTokenOut);
        require(fyTokenCachedCurrent + extraFYToken== pool.getFYTokenBalance());


    }
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
