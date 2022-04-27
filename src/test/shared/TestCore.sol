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
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {ISyncablePool} from "../mocks/ISyncablePool.sol";
import {IERC20Like} from  "../../interfaces/IERC20Like.sol";

// TestCore
// - Initializes state variables.
// - Sets state variable vm for accessing cheat codes.
// - Declares events,
// - Declares constants.
// No new contracts are created
abstract contract TestCore {
    event Liquidity(
        uint32 maturity,
        address indexed from,
        address indexed to,
        address indexed fyTokenTo,
        int256 bases,
        int256 fyTokens,
        int256 poolTokens
    );

    event Sync(uint112 baseCached, uint112 fyTokenCached, uint256 cumulativeBalancesRatio);

    event Trade(uint32 maturity, address indexed from, address indexed to, int256 bases, int256 fyTokens);

    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    Vm public vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    FYTokenMock public fyToken;
    ISyncablePool public pool;

    address public alice;
    address public bob;

    uint32 public maturity = uint32(block.timestamp + THREE_MONTHS);

    int128 public ts;

    int128 immutable k;

    uint16 public constant g1Fee = 9500;
    uint16 public constant g1Denominator = 10000;
    int128 public g1; // g to use when selling shares to pool
    int128 public g2; // g to use when selling fyTokens to pool

    uint256 public constant cNumerator = 11;
    uint256 public constant cDenominator = 10;

    uint256 public constant muNumerator = 105;
    uint256 public constant muDenominator = 100;
    int128 public mu;

    string public underlyingName;
    string public underlyingSymbol;
    uint8 public underlyingDecimals;
    ERC20Mock public underlying;

    string public fyName;
    string public fySymbol;

    bytes32 public baseType; // TYPE_4626 or TYPE_YV
    string public baseTypeString; // TYPE_4626 or TYPE_YV
    string public baseName;
    string public baseSymbol;
    IERC20Like public base;

    uint256 public aliceBaseInitialBalance;
    uint256 public bobBaseInitialBalance;

    uint256 public initialBase;
    uint256 public initialFYTokens;


    constructor() {
        uint256 invK = 25 * 365 * 24 * 60 * 60 * 10;
        k = uint256(1).fromUInt().div(invK.fromUInt());
        g1 = uint256(g1Fee).fromUInt().div(uint256(g1Denominator).fromUInt());
        g2 = uint256(g1Denominator).fromUInt().div(uint256(g1Fee).fromUInt());
        mu = muNumerator.fromUInt().div(muDenominator.fromUInt());
    }
}
