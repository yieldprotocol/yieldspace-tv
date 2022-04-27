// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import {PoolYearnVault} from "../../Pool/YearnVault/PoolYearnVault.sol";
import {ISyncablePool} from "./ISyncablePool.sol";

/// Pool with sync() added for ease in manipulating reserves ratio during testing.
contract SyncablePoolYearnVault is PoolYearnVault, ISyncablePool {

    constructor(
        address base_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) PoolYearnVault(base_, fyToken_, ts_, g1Fee_) {}

    /// Updates the cache to match the actual balances.  Useful for testing.  Risky for prod.
    function sync() public {
        _update(_getBaseBalance(), _getFYTokenBalance(), baseCached, fyTokenCached);
    }


}