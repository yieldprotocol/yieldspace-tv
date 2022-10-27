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
import {Exp64x64} from "../../../../Exp64x64.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import {ZeroState, ZeroStateParams} from "../../../shared/ZeroState.sol";

abstract contract ZeroStateEulerUSDT is ZeroState {
    using CastU256U128 for uint256;

    constructor() ZeroState(ZeroStateParams("USDT", "USDT", 6, "EulerVault", true)) {}
}

abstract contract WithLiquidityEulerUSDT is ZeroStateEulerUSDT {
    function setUp() public virtual override {
        super.setUp();

        shares.mint(address(pool), INITIAL_SHARES * 10**(shares.decimals()));
        vm.prank(alice);
        pool.init(alice);
        setPrice(address(shares), (cNumerator * (10**shares.decimals())) / cDenominator);
        uint256 additionalFYToken = (INITIAL_SHARES * 10**(asset.decimals())) / 9;

        fyToken.mint(address(pool), additionalFYToken);
        pool.sellFYToken(alice, 0);
    }
}

abstract contract WithExtraFYTokenEulerUSDT is WithLiquidityEulerUSDT {
    function setUp() public virtual override {
        super.setUp();
        uint256 additionalFYToken = 30 * 10**fyToken.decimals();
        fyToken.mint(address(pool), additionalFYToken);
        vm.prank(alice);
        pool.sellFYToken(address(alice), 0);
    }
}
