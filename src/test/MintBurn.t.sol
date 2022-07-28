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

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {ZeroState, ZeroStateParams} from "./shared/ZeroState.sol";

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

abstract contract ZeroStateDai is ZeroState {
    constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "4626")) {}
}

abstract contract WithLiquidity is ZeroStateDai {
    function setUp() public virtual override {
        super.setUp();

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));

        // Alice calls init.
        vm.prank(alice);
        pool.init(alice);

        // elapse some time after initialization
        vm.warp(block.timestamp + 60);

        // Update the price of shares to value of state variables: cNumerator/cDenominator
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(shares.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);

        // elapse some time after initialization
        vm.warp(block.timestamp + 60);
    }
}

contract Mint__ZeroState is ZeroStateDai {
    function testUnit_mint0() public {
        console.log("cannot mint before initialize or initialize without auth");

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_YVDAI);

        // Alice calls mint, but gets reverted.
        vm.expectRevert(abi.encodeWithSelector(NotInitialized.selector));
        vm.prank(alice);
        pool.mint(bob, bob, 0, MAX);

        // Setup new random user with no roles, and have them try to call init.
        address noAuth = payable(address(0xB0FFED));
        vm.expectRevert(bytes("Access denied"));
        vm.prank(noAuth);
        pool.init(bob);
    }

    function testUnit_mint1() public {
        console.log("adds initial liquidity");
        // Bob transfers some shares to the pool.
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
            int256(pool.mulMu(INITIAL_YVDAI))
        );

        // Alice calls init.
        vm.prank(alice);
        pool.init(bob);

        // Shares price is set to value of state variable cNumerator/cDenominator.
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);

        // Confirm balance of pool as expected, as well as cached balances.
        // First mint should equal shares in times mu
        require(pool.balanceOf(bob) == pool.mulMu(INITIAL_YVDAI));
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");

        // Send some shares to the pool.
        shares.mint(address(pool), INITIAL_YVDAI);

        // Alice calls init.
        vm.startPrank(alice);
        pool.init(address(0));

        // After initializing, donate shares and sellFyToken to simulate having reached zero fyToken through trading
        shares.mint(address(pool), INITIAL_YVDAI);
        pool.sellFYToken(alice, 0);

        // Send more shares to the pool.
        shares.mint(address(pool), INITIAL_YVDAI);

        // Alice calls mint
        pool.mint(bob, bob, 0, MAX);

        // Confirm balance of pool as expected, as well as cached balances.
        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        uint256 expectedLpTokens = (pool.totalSupply() * INITIAL_YVDAI) / sharesBal;
        require(pool.balanceOf(bob) == expectedLpTokens);
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    // Test intentionally ommitted.
    // function testUnit_mint3() public {
    //     console.log("syncs balances after donations");
}

contract Mint__WithLiquidity is WithLiquidity {
    function testUnit_mint4() public {
        console.log("mints liquidity tokens, returning surplus");

        // Calculate expected Mint and SharesIn for 1 WAD fyToken in.
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() * fyTokenIn) / fyToken.balanceOf(address(pool));
        uint256 expectedSharesIn = ((shares.balanceOf(address(pool)) * expectedMint) / pool.totalSupply());

        // send base for an extra wad of shares
        uint256 extraSharesIn = 1e18;
        uint256 expectedBaseIn = pool.unwrapPreview(expectedSharesIn + extraSharesIn);
        uint256 poolTokensBefore = pool.balanceOf(bob);

        // Send some base to the pool.
        asset.mint(address(pool), expectedBaseIn);
        // Send some fyToken to the pool.
        fyToken.mint(address(pool), fyTokenIn);

        // Alice calls mint to Bob.
        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        // Confirm minted amount is as expected.  Check balances and caches.
        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(shares.balanceOf(bob), bobSharesInitialBalance, fyTokenIn / 10000);
        almostEqual(asset.balanceOf(bob), pool.getCurrentSharePrice(), fyTokenIn / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint5() public {
        console.log("cannot initialize twice");
        vm.expectRevert(abi.encodeWithSelector(Initialized.selector));

        // Alice calls init.
        vm.startPrank(alice);
        pool.init(address(0));
    }
}

contract Burn__WithLiquidity is WithLiquidity {
    function testUnit_burn1() public {
        console.log("burns liquidity tokens");
        uint256 bobAssetBefore = asset.balanceOf(address(bob));
        uint256 sharesBalance = shares.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        address charlie = address(3);

        // Calculate expected shares and fytokens from the burn.
        uint256 expectedSharesOut = (lpTokensIn * sharesBalance) / poolSup;
        uint256 expectedAssetsOut = pool.unwrapPreview(expectedSharesOut);

        uint256 expectedFYTokenOut = (lpTokensIn * fyTokenBalance) / poolSup;

        // Alice transfers in lp tokens then burns them.
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

        // Alice calls burn.
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);

        // Confirm shares and fyToken out as expected and check balances pool and users.
        uint256 assetsOut = asset.balanceOf(address(bob)) - bobAssetBefore;
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        uint256 sharesOut = sharesBalance - shares.balanceOf(address(pool));
        almostEqual(sharesOut, expectedSharesOut, sharesOut / 10000);
        almostEqual(assetsOut, expectedAssetsOut, assetsOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (uint104 sharesBal, uint104 fyTokenBal, , ) = pool.getCache();
        require(sharesBal == pool.getSharesBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}
