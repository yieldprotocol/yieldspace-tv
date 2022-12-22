// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import {PoolYearnVault} from "../../Pool/Modules/PoolYearnVault.sol";
import {ISyncablePool} from "./ISyncablePool.sol";

/// Pool with sync() added for ease in manipulating reserves ratio during testing.
contract SyncablePoolYearnVault is PoolYearnVault, ISyncablePool {
    constructor(
        address shares_,
        address fyToken_,
        int128 ts_,
        uint16 g1Fee_
    ) PoolYearnVault(shares_, fyToken_, ts_, g1Fee_) {}

    /// Updates the cache to match the actual balances.  Useful for testing.  Risky for prod.
    function sync() public {
        _update(_getSharesBalance(), _getFYTokenBalance(), sharesReserves, fyTokenReserves);
    }

    function mulMu(uint256 amount) external view returns (uint256) {
        return _mulMu(amount);
    }

    function calcRatioSeconds(
        uint128 fyTokenReserves,
        uint128 sharesReserves,
        uint256 secondsElapsed
    ) public view returns (uint256) {
        return (uint256(fyTokenReserves) * 1e27 * secondsElapsed) / _mulMu(sharesReserves);
    }
}
