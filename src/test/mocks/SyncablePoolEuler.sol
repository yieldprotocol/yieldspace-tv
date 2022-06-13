// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import {PoolEuler} from "../../Pool/Modules/PoolEuler.sol";
import {ISyncablePool} from "./ISyncablePool.sol";

/// Pool with sync() added for ease in manipulating reserves ratio during testing.
contract SyncablePoolEuler is PoolEuler, ISyncablePool {

    constructor(
        address euler_,   // The main Euler contract address
        address shares_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) PoolEuler(euler_, shares_, fyToken_, ts_, g1Fee_) {}

    /// Updates the cache to match the actual balances.  Useful for testing.  Risky for prod.
    function sync() public {
        _update(_getSharesBalance(), _getFYTokenBalance(), sharesCached, fyTokenCached);
    }

    function getSharesSurplus() public view returns (uint128) {
        return _getSharesBalance() - sharesCached;
    }
}