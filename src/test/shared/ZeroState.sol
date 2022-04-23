// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Exp64x64} from "../../Exp64x64.sol";
import {Math64x64} from "../../Math64x64.sol";
import {YieldMath} from "../../YieldMath.sol";

import "./Utils.sol";
import "./Constants.sol";
import {TestCore} from "./TestCore.sol";
import {Pool} from "../../Pool/Pool.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {ERC4626TokenMock} from "../mocks/ERC4626TokenMock.sol";

bytes4 constant ROOT = 0x00000000;

struct ZeroStateParams {
    string fyName;
    string fySymbol;
    string baseName;
    string baseSymbol;
    uint8 baseDecimals;
}

abstract contract ZeroState is TestCore {
    using Exp64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for uint256;

    string public baseName;
    string public baseSymbol;
    uint8 public baseDecimals;

    string public fyName;
    string public fySymbol;

    constructor(ZeroStateParams memory params) {
        fyName = params.fyName;
        fySymbol = params.fySymbol;
        baseName = params.baseName;
        baseSymbol = params.baseSymbol;
        baseDecimals = params.baseDecimals;
    }

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup fyToken
        fyToken = new FYTokenMock(fyName, fySymbol, address(base), maturity);

        // setup users
        alice = address(0xbabe);
        vm.label(alice, "alice");
        bob = address(0xb0b);
        vm.label(bob, "bob");

    }
}
