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
import {SyncablePool} from "../mocks/SyncablePool.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {YVTokenMock} from "../mocks/YVTokenMock.sol";
import {IERC20Like} from "../../interfaces/IERC20Like.sol";
import {ERC4626TokenMock} from "../mocks/ERC4626TokenMock.sol";
import {SyncablePoolNonTv} from "../mocks/SyncablePoolNonTv.sol";
import {SyncablePoolYearnVault} from "../mocks/SyncablePoolYearnVault.sol";
import {AccessControl} from "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

bytes4 constant ROOT = 0x00000000;

struct ZeroStateParams {
    string assetName;
    string assetSymbol;
    uint8 assetDecimals;
    string baseType;
}

// ZeroState is the initial state of the protocol without any testable actions or state changes having taken place.
// Mocks are created, roles are granted, balances and initial prices are set.
// There is some complexity around baseType ("4626" or "YearnVault").
// If baseType is 4626:
//   - The base token is a ERC4626TokenMock cast as IERC20Like.
//   - The pool is a SyncablePool.sol cast as ISyncablePool.
// If baseType is YearnVault:
//   - The base token is a YVTokenMock cast as IERC20Like.
//   - The pool is a SyncablePoolYearnVault.sol cast as ISyncablePool.
// If baseType is NonTv (not tokenized vault -- regular token):
//   - The base token is is the underlying asset token cast as IERC20Like.
//   - The pool is a SyncablePoolNonTv.sol cast as ISyncablePool.
abstract contract ZeroState is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    constructor(ZeroStateParams memory params) {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt()); // TODO: UPDATE ME

        // Set underlying asset state variables.
        assetName = params.assetName;
        assetSymbol = params.assetSymbol;
        assetDecimals = params.assetDecimals;
        // Create and set asset token.
        asset = new ERC20Mock(assetName, assetSymbol, assetDecimals);

        // Set base token related variables.
        if (keccak256(abi.encodePacked(params.baseType)) == TYPE_NONTV) {
            baseName = params.assetName;
            baseSymbol = params.assetSymbol;
            baseType = keccak256(abi.encodePacked(params.baseType));
            baseTypeString = params.baseType;
        } else {
            baseName = string.concat(params.baseType, assetName);
            baseSymbol = string.concat(params.baseType, assetSymbol);
            baseType = keccak256(abi.encodePacked(params.baseType));
            baseTypeString = params.baseType;

        }

        // Set fyToken related variables.
        fySymbol = string.concat("fy", baseSymbol);
        fyName = string.concat("fyToken ", baseName, " maturity 1");

        // Set some state variables based on decimals, to use as constants.
        aliceBaseInitialBalance = 1000 * 10**(assetDecimals);
        bobBaseInitialBalance = 2_000_000 * 10**(assetDecimals);

        initialBase = 1_100_000 * 10**(assetDecimals);
        initialFYTokens = 1_500_000 * 10**(assetDecimals);
    }

    function setUp() public virtual {
        // Create base token (e.g. yvDAI)
        if (baseType == TYPE_NONTV) {
            base = IERC20Like(address(asset));
        } else {
            if (baseType == TYPE_4626) {
                base = IERC20Like(
                    address(new ERC4626TokenMock(baseName, baseSymbol, assetDecimals, address(asset)))
                );
            }
            if (baseType == TYPE_YV) {
                base = IERC20Like(address(new YVTokenMock(baseName, baseSymbol, assetDecimals, address(asset))));
            }
            setPrice(address(base), (muNumerator * (10**assetDecimals)) / muDenominator);
            asset.mint(address(base), 500_000_000 * 10**assetDecimals); // this is the vault reserves
        }

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
            pool = new SyncablePool(address(base), address(fyToken), ts, g1Fee);
        }
        if (baseType == TYPE_YV) {
            pool = new SyncablePoolYearnVault(address(base), address(fyToken), ts, g1Fee);
        }
        if (baseType == TYPE_NONTV) {
            pool = new SyncablePoolNonTv(address(base), address(fyToken), ts, g1Fee);
        }
        // Alice: init
        AccessControl(address(pool)).grantRole(bytes4(pool.init.selector), alice);
        // Bob  : setFees.
        AccessControl(address(pool)).grantRole(bytes4(pool.setFees.selector), bob);
    }
}
