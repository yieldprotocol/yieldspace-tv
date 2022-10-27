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
//    These tests are setup on the PoolEuler contract instead of the Pool contract
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
import "./State.sol";

contract Trade__WithLiquidityEulerUSDT is WithLiquidityEulerUSDT {
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU256U128 for uint256;

    function testUnit_Euler_tradeUSDT01() public {

    }
}
