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
import {Pool} from "../../Pool/Pool.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {ERC4626TokenMock} from "../mocks/ERC4626TokenMock.sol";

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

    ERC4626TokenMock public base;
    FYTokenMock public fyToken;
    Pool public pool;

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

    constructor() {
        uint256 invK = 25 * 365 * 24 * 60 * 60 * 10;
        k = uint256(1).fromUInt().div(invK.fromUInt());
        g1 = uint256(g1Fee).fromUInt().div(uint256(g1Denominator).fromUInt());
        g2 = uint256(g1Denominator).fromUInt().div(uint256(g1Fee).fromUInt());
        mu = muNumerator.fromUInt().div(muDenominator.fromUInt());
    }
}
