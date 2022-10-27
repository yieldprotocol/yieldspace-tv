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

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//
//    NOTE:
//    These tests are exactly copy and pasted from the MintBurn.t.sol and TradingUSDC.t.sol test suites.
//    The only difference is they are setup on the PoolEuler contract instead of the Pool contract
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../Pool/PoolErrors.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import {ETokenMock} from "../../../mocks/ETokenMock.sol";
import {IERC20Like} from "../../../../interfaces/IERC20Like.sol";
import "./State.sol";

contract SetFeesEulerUSDT is ZeroStateEulerUSDT {
    using Math64x64 for uint256;

    function testUnit_Euler_setFeesUSDT01() public {
        console.log("does not set invalid fee");

        uint16 g1Fee_ = 10001;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(InvalidFee.selector, g1Fee_));
        pool.setFees(g1Fee_);
    }

    function testUnit_Euler_setFeesUSDT02() public {
        console.log("does not set fee without auth");

        uint16 g1Fee_ = 9000;

        vm.prank(alice);
        vm.expectRevert("Access denied");
        pool.setFees(g1Fee_);
    }

    function testUnit_Euler_setFeesUSDT03() public {
        console.log("sets valid fee");

        uint16 g1Fee_ = 8000;
        int128 expectedG1 = uint256(g1Fee_).divu(10000);
        int128 expectedG2 = uint256(10000).divu(g1Fee_);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit FeesSet(g1Fee_);

        pool.setFees(g1Fee_);

        assertEq(pool.g1(), expectedG1);
        assertEq(pool.g2(), expectedG2);
    }
}

contract Mint_ZeroStateEulerUSDT is ZeroStateEulerUSDT {
    function testUint_Euler_mintUSDT01() public {
        console.log("adds initial liquidity");

        
    }
}