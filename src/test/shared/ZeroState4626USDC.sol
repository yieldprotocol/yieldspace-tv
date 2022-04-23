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
import {ZeroState, ZeroStateParams} from "./ZeroState.sol";
import {Pool} from "../../Pool/Pool.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {ERC4626TokenMock} from "../mocks/ERC4626TokenMock.sol";

bytes4 constant ROOT = 0x00000000;


abstract contract ZeroState4626 is ZeroState {
    using Exp64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for uint256;


    constructor(ZeroStateParams memory params) ZeroState(params) {
        super.setUp();

        // setup base
        base = new ERC4626TokenMock(baseName, baseSymbol, baseDecimals, address(0));
        base.setPrice((muNumerator * (10**base.decimals())) / muDenominator);

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1Fee);
        pool.grantRole(bytes4(pool.init.selector), alice);
        pool.grantRole(bytes4(pool.setFees.selector), bob);

    }

    function setUp() public virtual {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());
        // setup mock tokens
        base = new ERC4626TokenMock(baseName, baseSymbol, baseDecimals, address(0));
        base.setPrice((muNumerator * (10**base.decimals())) / muDenominator);
        fyToken = new FYTokenMock(fyName, fySymbol, address(base), maturity);

        // setup users
        alice = address(0xbabe);
        vm.label(alice, "alice");
        bob = address(0xb0b);
        vm.label(bob, "bob");

        // setup pool
        pool = new Pool(address(base), address(fyToken), ts, g1Fee);
        pool.grantRole(bytes4(pool.init.selector), alice);
        pool.grantRole(bytes4(pool.setFees.selector), bob);

    }
}

abstract contract ZeroState4626USDC is ZeroState4626 {
    // used in 2 test suites __WithLiquidity

    uint256 public constant aliceBaseInitialBalance = 1000 * 1e6;
    uint256 public constant bobBaseInitialBalance = 2_000_000 * 1e6;

    uint256 public constant initialFYTokens = 1_500_000 * 1e6;
    uint256 public constant initialBase = 1_100_000 * 1e6;

    ZeroStateParams public zeroStateParams =
        ZeroStateParams("fyTVUSDC1", "fyToken tvUSDC maturity 1", "tvUSDC", "Tokenized Vault USDC", 6);

    constructor() ZeroState4626(zeroStateParams) {}

    function setUp() public virtual override {
        super.setUp();

        base.mint(alice, aliceBaseInitialBalance);
        base.mint(bob, bobBaseInitialBalance);
    }
}
