// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Exp64x64} from "../../Exp64x64.sol";
import {Math64x64} from "../../Math64x64.sol";
import {YieldMath} from "../../YieldMath.sol";

import {ERC20} from "../../Pool/PoolImports.sol";
import {ISyncablePool} from "../mocks/ISyncablePool.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";

import "./Utils.sol";
import "./Constants.sol";

// ForkTestCore
// - Initializes state variables.
// - Sets state variable vm for accessing cheat codes.
// - Declares events,
// - Declares constants.
// No new contracts are created
abstract contract ForkTestCore is Test {
    event FeesSet(uint16 g1Fee);

    event Liquidity(
        uint32 maturity,
        address indexed from,
        address indexed to,
        address indexed fyTokenTo,
        int256 shares,
        int256 fyTokens,
        int256 poolTokens
    );

    event Sync(uint112 sharesCached, uint112 fyTokenCached, uint256 cumulativeBalancesRatio);

    event Trade(uint32 maturity, address indexed from, address indexed to, int256 shares, int256 fyTokens);

    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    ISyncablePool public pool;
    ERC20 public asset;
    FYTokenMock public fyToken;

    address public alice;
    address public bob;
    address public whale;
    address public timelock;
    address public ladle = 0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A;
}
