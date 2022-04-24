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
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {YVTokenMock} from "../mocks/YVTokenMock.sol";
import {IERC20Like} from "../../interfaces/IERC20Like.sol";
import {ERC4626TokenMock} from "../mocks/ERC4626TokenMock.sol";
import {PoolYearnVault} from "../../Pool/YearnVault/PoolYearnVault.sol";
import {AccessControl} from "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

bytes4 constant ROOT = 0x00000000;

struct ZeroStateParams {
    string underlyingName;
    string underlyingSymbol;
    uint8 underlyingDecimals;
    string baseType;
}

// ZeroState is the initial state of the protocol without any testable actions or state changes having taken place.
// Mocks are created, roles are granted, balances and initial prices are set.
// There is some complexity around baseType ("4626" or "YearnVault").
// If baseType is 4626:
//   - The base token is a ERC4626TokenMock cast as IERC20Like.
//   - The Pool is a Pool.sol cast as IPool.sol.
// If baseType is YearnVault:
//   - The base token is a YVTokenMock cast as IERC20Like.
//   - The Pool is a PoolYearnVault.sol cast as IPool.sol.
abstract contract ZeroState is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    constructor(ZeroStateParams memory params) {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt()); // TODO: UPDATE ME

        // Set underlying state variables.
        underlyingName = params.underlyingName;
        underlyingSymbol = params.underlyingSymbol;
        underlyingDecimals = params.underlyingDecimals;
        // Create and set underlying token.
        underlying = new ERC20Mock(underlyingName, underlyingSymbol, underlyingDecimals);

        // Set base token related variables.
        baseName = string.concat(params.baseType, underlyingName);
        baseSymbol = string.concat(params.baseType, underlyingSymbol);
        baseType = keccak256(abi.encodePacked(params.baseType));
        baseTypeString = params.baseType;

        // Set fyToken related variables.
        fySymbol = string.concat("fy", baseSymbol);
        fyName = string.concat("fyToken ", baseName, " maturity 1");

        // Set some state variables based on decimals, to use as constants.
        aliceBaseInitialBalance = 1000 * 10**(underlyingDecimals);
        bobBaseInitialBalance = 2_000_000 * 10**(underlyingDecimals);

        initialBase = 1_100_000 * 10**(underlyingDecimals);
        initialFYTokens = 1_500_000 * 10**(underlyingDecimals);
    }

    function setUp() public virtual {
        // Create base token (e.g. yvDAI)
        if (baseType == TYPE_4626) {
            base = IERC20Like(
                address(new ERC4626TokenMock(baseName, baseSymbol, underlyingDecimals, address(underlying)))
            );
        }
        if (baseType == TYPE_YV) {
            base = IERC20Like(address(new YVTokenMock(baseName, baseSymbol, underlyingDecimals, address(underlying))));
        }
        setPrice(address(base), (muNumerator * (10**underlyingDecimals)) / muDenominator);

        // Create fyToken (e.g. "fyyvDAI").
        fyToken = new FYTokenMock(fyName, fySymbol, address(base), maturity);

        // Setup users, and give them some base.
        alice = address(0xbabe);
        vm.label(alice, "alice");
        base.mint(alice, aliceBaseInitialBalance);

        bob = address(0xb0b);
        vm.label(bob, "bob");
        base.mint(bob, bobBaseInitialBalance);

        // Setup pool and grant roles:
        if (baseType == TYPE_4626) {
            pool = new Pool(address(base), address(fyToken), ts, g1Fee);
        }
        if (baseType == TYPE_YV) {
            pool = new PoolYearnVault(address(base), address(fyToken), ts, g1Fee);
        }

        // Alice: init
        AccessControl(address(pool)).grantRole(bytes4(pool.init.selector), alice);
        // Bob  : setFees.
        AccessControl(address(pool)).grantRole(bytes4(pool.setFees.selector), bob);
    }
}
