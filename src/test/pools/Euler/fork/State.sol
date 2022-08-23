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
//    State for mainnet fork test environment
//
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import "../../../../Pool/PoolErrors.sol";
import {ERC20, AccessControl} from "../../../../Pool/PoolImports.sol";
import {ISyncablePool} from "../../../mocks/ISyncablePool.sol";
import {FYTokenMock} from "../../../mocks/FYTokenMock.sol";
import {Exp64x64} from "../../../../Exp64x64.sol";
import {Math64x64} from "../../../../Math64x64.sol";
import {YieldMath} from "../../../../YieldMath.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../../shared/Utils.sol";
import "../../../shared/Constants.sol";
import {ForkTestCore} from "../../../shared/ForkTestCore.sol";

abstract contract EulerDAIFork is ForkTestCore {
    function fundAddr(address addr) public {
        vm.prank(whale);
        asset.transfer(addr, WAD * 100_000);

        vm.prank(ladle);
        fyToken.mint(addr, WAD * 100_000);
    }

    function setUp() public virtual {
        pool = ISyncablePool(MAINNET_DAI_DECEMBER_2022_POOL);
        asset = ERC20(MAINNET_DAI);
        fyToken = FYTokenMock(0xcDfBf28Db3B1B7fC8efE08f988D955270A5c4752);
        alice = address(0xbabe);
        bob = address(0xb0b);
        whale = address(0x5D38B4e4783E34e2301A2a36c39a03c45798C4dD);
        timelock = address(0x3b870db67a45611CF4723d44487EAF398fAc51E3);
        ladle = address(0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A);

        fundAddr(alice);
    }
}

abstract contract EulerDAIForkWithLiquidity is EulerDAIFork {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(alice);

        // try to mint pool tokens
        asset.transfer(address(pool), WAD * 5000);
        fyToken.transfer(address(pool), (WAD * 5000) / 2);
        pool.mint(alice, alice, 0, MAX);

        vm.stopPrank();
    }
}
