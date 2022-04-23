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
import {ZeroState4626DAI} from "./shared/ZeroState4626DAI.sol";

import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";

abstract contract WithLiquidity is ZeroState4626DAI {
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

contract Admin__WithLiquidity is WithLiquidity {
    function testUnit_admin1() public {
        console.log("balance management getters return correct values");
        require(pool.getBaseBalance() == base.balanceOf(address(pool)));
        require(pool.getBaseCurrentPrice() == base.convertToAssets(10**base.decimals()));
        require(pool.getFYTokenBalance() == fyToken.balanceOf(address(pool)) + pool.totalSupply());
        (uint16 g1fee_, uint104 baseCached, uint104 fyTokenCached, uint32 blockTimeStampLast) = pool.getCache();
        require(g1fee_ == g1Fee);
        require(baseCached == 1100000000000000000000000);
        require(fyTokenCached == 1222222222222222222222222);
        require(blockTimeStampLast > 0);
        uint256 expectedCurrentCumulativeRatio = pool.cumulativeRatioLast() +
            ((uint256(fyTokenCached) * 1e27) * (block.timestamp - blockTimeStampLast)) /
            baseCached;
        (uint256 actualCurrentCumulativeRatio, ) = pool.currentCumulativeRatio();
        require(actualCurrentCumulativeRatio == expectedCurrentCumulativeRatio);
        base.mint(address(pool), 1e18);
        pool.sync();
        (,uint104 baseCachedNew,,) = pool.getCache();
        require(baseCachedNew == baseCached + 1e18);

    }

    function testUnit_admin2() public {
        console.log("setFees cannot be set without auth");

        vm.expectRevert(bytes("Access denied"));
        pool.setFees(600);

        vm.prank(bob);
        pool.setFees(600);
    }
}
