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

import "../../shared/Utils.sol";
import "../../shared/Constants.sol";
import {WithLiquidity} from "./MintBurn.t.sol";

import "../../../Pool/PoolErrors.sol";
import {Exp64x64} from "../../Exp64x64.sol";
import {Math64x64} from "../../../Math64x64.sol";
import {YieldMath} from "../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

contract WrapUnwrap__WithLiquidity is WithLiquidity {
    using CastU256U128 for uint256;

    function testUnit_wrap() public {
        console.log("wrap preview matches wrap");

        uint256 assetIn = 1_000 * 10**asset.decimals();
        uint256 expectedShares = pool.wrapPreview(assetIn);
        asset.mint(alice, assetIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 sharesBalBefore = shares.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), assetIn);
        pool.wrap(alice);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 sharesBalAfter = shares.balanceOf(alice);

        assertEq(assetBalBefore - assetBalAfter, assetIn);
        assertEq(sharesBalAfter - sharesBalBefore, expectedShares);
    }

    function testUnit_unwrap() public {
        console.log("unwrap preview matches unwrap");

        uint256 sharesIn = 1_000 * 10**shares.decimals();
        uint256 expectedAsset = pool.unwrapPreview(sharesIn);
        shares.mint(alice, sharesIn);

        uint256 assetBalBefore = asset.balanceOf(alice);
        uint256 sharesBalBefore = shares.balanceOf(alice);

        vm.startPrank(alice);
        shares.transfer(address(pool), sharesIn);
        pool.unwrap(alice);

        uint256 assetBalAfter = asset.balanceOf(alice);
        uint256 sharesBalAfter = shares.balanceOf(alice);

        assertEq(assetBalAfter - assetBalBefore, expectedAsset);
        assertEq(sharesBalBefore - sharesBalAfter, sharesIn);
    }

    function testUnit_wrap_unwrap() public {
        console.log("wrapping then unwrapping gives you original amount");

        uint256 assetIn = 1_000 * 10**asset.decimals();
        uint256 expectedShares = pool.wrapPreview(assetIn);
        uint256 expectedAssetOut = pool.unwrapPreview(expectedShares);
        asset.mint(alice, assetIn);

        uint256 assetBalBefore = asset.balanceOf(alice);

        vm.startPrank(alice);
        asset.transfer(address(pool), assetIn);
        pool.wrap(address(pool));
        pool.unwrap(alice);

        uint256 assetBalAfter = asset.balanceOf(alice);
        assertEq(assetBalAfter, assetBalBefore);
        assertEq(assetIn, expectedAssetOut);
    }
}
