// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import {IPool} from "../../interfaces/IPool.sol";

/// Pool with sync() added for ease in manipulating reserves ratio during testing.
interface ISyncablePool is IPool {
    function sync() external;
}

