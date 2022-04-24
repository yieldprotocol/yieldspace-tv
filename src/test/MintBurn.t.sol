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

import "./shared/Utils.sol";
import "./shared/Constants.sol";
import {ZeroState, ZeroStateParams} from "./shared/ZeroState.sol";

import "../Pool/PoolErrors.sol";
import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

abstract contract ZeroStateDai is ZeroState{
    constructor() ZeroState(ZeroStateParams("DAI", "DAI", 18, "4626")) {}

}

abstract contract WithLiquidity is ZeroStateDai {

    function setUp() public virtual override {
        super.setUp();

        // Send some base to the pool.
        base.mint(address(pool), INITIAL_BASE * 10**(base.decimals()));

        // Alice calls init.
        vm.prank(alice);
        pool.init(alice, bob, 0, MAX);

        // Update the price of base to value of state variables: cNumerator/cDenominator
        setPrice(address(base), (cNumerator * (10**base.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_BASE * 10**(base.decimals())) / 9;

        // Skew the balances by donating fyToken, without using trading functions.
        fyToken.mint(address(pool), additionalFYToken);
        pool.sync();
    }
}

contract Mint__ZeroState is ZeroStateDai {
    function testUnit_mint0() public {
        console.log("cannot mint before initialize or initialize without auth");

        // Send some base to the pool.
        base.mint(address(pool), INITIAL_YVDAI);

        // Alice calls mint, but gets reverted.
        vm.expectRevert(abi.encodeWithSelector(NotInitialized.selector));
        vm.prank(alice);
        pool.mint(bob, bob, 0, MAX);

        // Setup new random user with no roles, and have them try to call init.
        address noAuth = payable(address(0xB0FFED));
        vm.expectRevert(bytes("Access denied"));
        vm.prank(noAuth);
        pool.init(bob, bob, 0, MAX);
    }

    function testUnit_mint1() public {
        console.log("adds initial liquidity");

        // Bob transfers some base to the pool.
        vm.prank(bob);
        base.transfer(address(pool), INITIAL_YVDAI);

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

        // Alice calls init.
        vm.prank(alice);
        pool.init(bob, bob, 0, MAX);

        // Base price is set to value of state variable cNumerator/cDenominator.
        setPrice(address(base), (cNumerator * (10**base.decimals())) / cDenominator);

        // Confirm balance of pool as expected, as well as cached balances.
        require(pool.balanceOf(bob) == INITIAL_YVDAI);
        (, uint104 baseBal, uint104 fyTokenBal, ) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint2() public {
        console.log("adds liquidity with zero fyToken");

        // Send some base to the pool.
        base.mint(address(pool), INITIAL_YVDAI);

        // Alice calls init.
        vm.startPrank(alice);
        pool.init(address(0), address(0), 0, MAX);

        // After initializing, donate base and sync to simulate having reached zero fyToken through trading
        base.mint(address(pool), INITIAL_YVDAI);
        pool.sync();

        // Send more base to the pool.
        base.mint(address(pool), INITIAL_YVDAI);

        // Alice calls mint
        pool.mint(bob, bob, 0, MAX);

        // Confirm balance of pool as expected, as well as cached balances.
        require(pool.balanceOf(bob) == INITIAL_YVDAI / 2);
        (, uint104 baseBal, uint104 fyTokenBal, ) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint3() public {
        console.log("syncs balances after donations");

        // Send some base to the pool.
        base.mint(address(pool), INITIAL_YVDAI);
        // Send some fyToken to the pool.
        fyToken.mint(address(pool), INITIAL_YVDAI / 9);

        vm.expectEmit(false, false, false, true);
        emit Sync(uint104(INITIAL_YVDAI), uint104(INITIAL_YVDAI / 9), 0);

        // Alice calls sync.
        vm.prank(alice);
        pool.sync();

        // Confirm balance of pool as expected, as well as cached balances.
        (, uint104 baseBal, uint104 fyTokenBal, ) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }
}

contract Mint__WithLiquidity is WithLiquidity {
    function testUnit_mint4() public {
        console.log("mints liquidity tokens, returning base surplus");

        // Calculate expected Mint and BaseIn for 1 WAD fyToken in.
        uint256 fyTokenIn = WAD;
        uint256 expectedMint = (pool.totalSupply() / (fyToken.balanceOf(address(pool)))) * 1e18;
        uint256 expectedBaseIn = (base.balanceOf(address(pool)) * expectedMint) / pool.totalSupply();

        uint256 poolTokensBefore = pool.balanceOf(bob);

        // Send some base to the pool.
        base.mint(address(pool), expectedBaseIn + 1e18); // send an extra wad of base
        // Send some fyToken to the pool.
        fyToken.mint(address(pool), fyTokenIn);

        // Alice calls mint.
        vm.startPrank(alice);
        pool.mint(bob, bob, 0, MAX);

        uint256 minted = pool.balanceOf(bob) - poolTokensBefore;

        // Confirm minted amount is as expected.  Check balances and caches.
        almostEqual(minted, expectedMint, fyTokenIn / 10000);
        almostEqual(base.balanceOf(bob), WAD + bobBaseInitialBalance, fyTokenIn / 10000);

        (, uint104 baseBal, uint104 fyTokenBal, ) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
    }

    function testUnit_mint5() public {
        console.log("cannot initialize twice");
        vm.expectRevert(abi.encodeWithSelector(Initialized.selector));

       // Alice calls init.
        vm.startPrank(alice);
        pool.init(address(0), address(0), 0, MAX);
    }
}

contract Burn__WithLiquidity is WithLiquidity {
    function testUnit_burn1() public {
        console.log("burns liquidity tokens");
        uint256 baseBalance = base.balanceOf(address(pool));
        uint256 fyTokenBalance = fyToken.balanceOf(address(pool));
        uint256 poolSup = pool.totalSupply();
        uint256 lpTokensIn = WAD;

        address charlie = address(3);

        // Calculate expected base and fytokens from the burn.
        uint256 expectedBaseOut = (lpTokensIn * baseBalance) / poolSup;
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
            int256(expectedBaseOut),
            int256(expectedFYTokenOut),
            -int256(lpTokensIn)
        );

        // Alice calls burn.
        vm.prank(alice);
        pool.burn(bob, address(charlie), 0, MAX);


        // Confirm base and fyToken out as expected and check balances pool and users.
        uint256 baseOut = baseBalance - base.balanceOf(address(pool));
        uint256 fyTokenOut = fyTokenBalance - fyToken.balanceOf(address(pool));
        almostEqual(baseOut, expectedBaseOut, baseOut / 10000);
        almostEqual(fyTokenOut, expectedFYTokenOut, fyTokenOut / 10000);

        (, uint104 baseBal, uint104 fyTokenBal, ) = pool.getCache();
        require(baseBal == pool.getBaseBalance());
        require(fyTokenBal == pool.getFYTokenBalance());
        require(base.balanceOf(bob) - bobBaseInitialBalance == baseOut);
        require(fyToken.balanceOf(address(charlie)) == fyTokenOut);
    }
}
