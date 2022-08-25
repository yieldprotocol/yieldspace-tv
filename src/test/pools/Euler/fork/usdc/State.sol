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

import "../../../../../Pool/PoolErrors.sol";
import {Exp64x64} from "../../../../Exp64x64.sol";
import {Math64x64} from "../../../../../Math64x64.sol";
import {YieldMath} from "../../../../../YieldMath.sol";
import {Pool} from "../../../../../Pool/Pool.sol";
import {ERC20, AccessControl} from "../../../../../Pool/PoolImports.sol";
// Using FYTokenMock.sol here for the interface so we don't need to add a new dependency
// to this repo just to get an interface:
import {FYTokenMock as FYToken} from "../../../../mocks/FYTokenMock.sol";
import {CastU256U128} from "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";

import "../../../../shared/Utils.sol";
import "../../../../shared/Constants.sol";
import {ForkTestCore} from "../../../../shared/ForkTestCore.sol";
import {IEToken} from "../../../../../interfaces/IEToken.sol";

abstract contract EulerUSDCFork is ForkTestCore {
    address public whale = address(0xbd50C26f7ed3dE3f642149D487f4308a42763bd6);
    uint8 decimals;
    uint256 WAD; // scaled to asset decimals

    function fundAddr(address addr) public {
        vm.prank(whale);
        asset.transfer(addr, (WAD * 100_000)); // scale for usdc decimals

        vm.prank(ladle);
        fyToken.mint(addr, (WAD * 100_000)); // scale for usdc decimals
    }

    function setUp() public virtual {
        pool = Pool(MAINNET_USDC_DECEMBER_2022_POOL);
        asset = ERC20(address(pool.baseToken()));
        fyToken = FYToken(address(pool.fyToken()));
        shares = IEToken(address(pool.sharesToken()));
        WAD = 1e18 / (10**(18 - asset.decimals()));

        fundAddr(alice);
    }
}

abstract contract EulerUSDCForkWithLiquidity is EulerUSDCFork {
    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(alice);

        // try to mint pool tokens
        asset.transfer(address(pool), (WAD * 5000)); // scale for usdc decimals
        fyToken.transfer(address(pool), (WAD * 5000) / 2); // scale for usdc decimals
        pool.mint(alice, alice, 0, MAX);

        vm.stopPrank();
    }
}
