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
        console.log("sells a certain amount of fyToken for shares");
        uint256 fyTokenIn = 25_000 * 1e18;

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10 ** shares.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

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
        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, int256(expectedSharesOut), -int256(fyTokenIn));

        // Alice calls sellFYToken.
        vm.prank(alice);
        pool.sellFYToken(bob, 0);

        // Confirm cached balances are updated properly.
        (, uint104 sharesBal, uint104 fyTokenBal,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
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
    //     console.log("donating shares does not affect cache balances when selling fyToken");

    //     uint256 sharesDonation = WAD;
    //     uint256 fyTokenIn = WAD;

    //     // Donate shares and fyToken to pool.
    //     shares.mint(address(pool), sharesDonation);
    //     fyToken.mint(address(pool), fyTokenIn);

    //     // Bob calls sellFYToken
    //     vm.prank(bob);
    //     pool.sellFYToken(bob, 0);

    //     // Check cached balances are udpated correctly.
    //     (, uint104 sharesBal, uint104 fyTokenBal,) = pool.getCache();
    //     require(sharesBal == pool.getSharesBalance() - sharesDonation);
    //     require(fyTokenBal == pool.getFYTokenBalance());
    // }

    function testUnit_tradeDAI04() public {
        console.log("buys a certain amount shares for fyToken");
        (, , uint104 fyTokenBalBefore,) = pool.getCache();

        uint256 userSharesBefore = shares.balanceOf(bob);
        uint256 userAssetBefore = asset.balanceOf(bob);

        uint128 sharesOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10 ** shares.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

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
        emit Trade(maturity, bob, bob, int256(int128(sharesOut)), -int256(expectedFYTokenIn));

        // Bob calls buyBase
        vm.prank(bob);
        pool.buyBase(bob, uint128(sharesOut), type(uint128).max);

        // Check cached balances are udpated correctly.
        (, , uint104 fyTokenBal,) = pool.getCache();
        uint256 fyTokenIn = fyTokenBal - fyTokenBalBefore;
        uint256 fyTokenChange = pool.getFYTokenBalance() - fyTokenBal;

        require(shares.balanceOf(bob) == userSharesBefore);
        require(asset.balanceOf(bob) == userAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut));

        almostEqual(fyTokenIn, expectedFYTokenIn, sharesOut / 1000000);

        (, uint104 sharesBalAfter, uint104 fyTokenBalAfter,) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter + fyTokenChange == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI05() public {
        console.log("does not buy shares beyond slippage");
        uint128 sharesOut = 1e18;

        // Send 1 WAD fyToken to pool.
        fyToken.mint(address(pool), initialFYTokens);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyBase.selector, 1100063607139041184, 0)
        );

        // Set maxRatio to 0 and see it revert.
        pool.buyBase(bob, sharesOut, 0);
    }

    function testUnit_tradeDAI06() public {
        console.log("when buying shares, donating fyToken and extra shares doesn't get absorbed and the shares is unwrapped and sent back");
        // TODO: Not sure this tests is necessary as the dynamics have changed.  Here is what the old test did:
        // console.log("when buying shares, donating fyToken and extra shares doesn't get absorbed and can be retrieved");
        uint256 aliceSharesBefore = shares.balanceOf(alice);
        uint256 bobSharesBefore = shares.balanceOf(bob);
        uint256 bobAssetBefore = asset.balanceOf(bob);
        uint256 aliceFYTokenBefore = fyToken.balanceOf(alice);
        uint128 sharesOut = uint128(WAD * 10);
        uint128 expectedFYTokenIn = pool.buyBasePreview(sharesOut);
        uint128 extraFYToken = uint128(5 * 1e17); // half wad
        uint128 extraShares = uint128(WAD) * 5;


        // Send some fyTokens to the pool.
        fyToken.mint(address(pool), expectedFYTokenIn + extraFYToken);
        shares.mint(address(pool), extraShares);

        // Alice call buyBase, check balances are as expected.
        vm.startPrank(alice);
        pool.buyBase(bob, sharesOut, uint128(MAX));
        require(shares.balanceOf(bob) == bobSharesBefore);
        (, uint104 sharesBal, uint104 fyTokenBal,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance() - extraFYToken);
        require(asset.balanceOf(bob) == bobAssetBefore + IERC4626Mock(address(shares)).convertToAssets(sharesOut + extraShares));
        pool.retrieveFYToken(alice);
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());

        require(fyToken.balanceOf(alice) == aliceFYTokenBefore + extraFYToken);
    }
}

contract TradeDAI__WithExtraFYToken is WithExtraFYToken {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    function testUnit_tradeDAI07() public {
        console.log("sells shares for a certain amount of FYTokens");
        uint256 aliceBeginningSharesBal = shares.balanceOf(alice);
        uint128 sharesIn = uint128(WAD);
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10 ** shares.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer shares for sale to the pool.
        shares.mint(address(pool), sharesIn);

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
        emit Trade(maturity, alice, bob, -int128(sharesIn), int256(expectedFYTokenOut));

        // Alice calls sellBase.  Confirm amounts and balances as expected.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        uint256 fyTokenOut = fyToken.balanceOf(bob) - userFYTokenBefore;
        require(aliceBeginningSharesBal == shares.balanceOf(alice), "'From' wallet should have not increase shares tokens");
        require(fyTokenOut == expectedFYTokenOut);
        (, uint104 sharesBal, uint104 fyTokenBal,) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_tradeDAI08() public {
        console.log("does not sell shares beyond slippage");
        uint128 sharesIn = uint128(WAD);

        // Send 1 WAD shares to the pool.
        shares.mint(address(pool), sharesIn);

        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringSellBase.selector, 1100059305930990583, 340282366920938463463374607431768211455)
        );
        // Set min acceptable amount to uint128.max and see it revert.
        vm.prank(alice);
        pool.sellBase(bob, uint128(MAX));
    }

    function testUnit_tradeDAI09() public {
        console.log("donating fyToken does not affect cache balances when selling shares");
        uint128 sharesIn = uint128(WAD);
        uint128 fyTokenDonation = uint128(WAD);

        // Donate both fyToken and shares to the pool.
        fyToken.mint(address(pool), fyTokenDonation);
        shares.mint(address(pool), sharesIn);

        // Alice calls sellBase. See confirm cached balances.
        vm.prank(alice);
        pool.sellBase(bob, 0);

        (, uint104 sharesBalAfter, uint104 fyTokenBalAfter,) = pool.getCache();

        require(sharesBalAfter == pool.getSharesBalance());
        require(fyTokenBalAfter == pool.getFYTokenBalance() - fyTokenDonation);
    }

    function testUnit_tradeDAI10() public {
        console.log("buys a certain amount of fyTokens with shares");
        (, uint104 sharesCachedBefore,,) = pool.getCache();
        uint256 userFYTokenBefore = fyToken.balanceOf(bob);
        uint128 fyTokenOut = uint128(WAD);

        uint128 virtFYTokenBal = uint128(fyToken.balanceOf(address(pool)) + pool.totalSupply());
        uint128 sharesReserves = uint128(shares.balanceOf(address(pool)));
        int128 c_ = (IERC4626Mock(address(shares)).convertToAssets(10 ** shares.decimals()).fromUInt()).div(uint256(1e18).fromUInt());

        // Transfer shares for sale to the pool.
        shares.mint(address(pool), initialShares);

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

        vm.expectEmit(true, true, false, true);
        emit Trade(maturity, alice, bob, -int128(int256(expectedSharesIn)), int256(int128(fyTokenOut)));

        // Alice calls buyFYToken.  Confirm caches and user balances.  Confirm sharesIn is as expected.
        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));

        (, uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent,) = pool.getCache();

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

    function testUnit_tradeDAI11() public {
        console.log("does not buy fyToken beyond slippage");
        uint128 fyTokenOut = uint128(WAD);

        // Send some shares to the pool.
        shares.mint(address(pool), initialShares);
        vm.expectRevert(
            abi.encodeWithSelector(SlippageDuringBuyFYToken.selector, 909042724853432477, 0)
        );

        // Set max amount out to 0 and watch it revert.
        pool.buyFYToken(alice, fyTokenOut, 0);
    }

    function testUnit_tradeDAI12() public {
        console.log("donating fyToken and extra shares doesn't get absorbed into the cache when buying fyTokens");
        uint256 sharesBalance = pool.getSharesBalance();
        uint256 fyTokenBalance = pool.getFYTokenBalance();
        (, uint104 sharesCachedBefore,,) = pool.getCache();

        uint128 fyTokenOut = uint128(WAD * 10);
        uint128 expectedSharesIn = pool.buyFYTokenPreview(fyTokenOut);
        uint128 extraShares = uint128(WAD) * 5;
        uint128 extraFYToken = uint128(5 * 1e17); // half wad

       // Send some shares to the pool.
        shares.mint(address(pool), expectedSharesIn + extraShares);
        fyToken.mint(address(pool), extraFYToken);
        require(pool.getSharesBalance() == sharesBalance + extraShares + expectedSharesIn);

        // Alice does buyFYToken. Confirm caches and balances.
        vm.prank(alice);
        pool.buyFYToken(bob, fyTokenOut, uint128(MAX));
        require(pool.getSharesBalance() == sharesBalance + extraShares + expectedSharesIn);
        (, uint104 sharesCachedCurrent, uint104 fyTokenCachedCurrent,) = pool.getCache();
        uint256 sharesIn = sharesCachedCurrent - sharesCachedBefore;
        require(sharesCachedCurrent == sharesBalance + sharesIn);
        require(sharesCachedCurrent + extraShares == pool.getSharesBalance());
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
