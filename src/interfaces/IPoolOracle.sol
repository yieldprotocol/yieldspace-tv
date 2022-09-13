// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import "./IPool.sol";

interface IPoolOracle {
    /// @notice returns the TWAR for a given `pool` using the moving average over the max available time range within the window
    /// @param pool Address of pool for which the observation is required
    /// @return twar The most up to date TWAR for `pool`
    function peek(IPool pool) external view returns (uint256 twar);

    /// @notice returns the TWAR for a given `pool` using the moving average over the max available time range within the window
    /// @dev will try to record a new observation if necessary, so equivalent to `update(pool); peek(pool);`
    /// @param pool Address of pool for which the observation is required
    /// @return twar The most up to date TWAR for `pool`
    function get(IPool pool) external returns (uint256 twar);

    /// @notice updates the cumulative ratio for the observation at the current timestamp. Each observation is updated at most
    /// once per epoch period.
    /// @param pool Address of pool for which the observation should be recorded
    function update(IPool pool) external;

    function buyBasePreview(IPool pool, uint256 baseOut) external returns (uint256 fyTokenIn, uint256 updateTime);

    function buyFYTokenPreview(IPool pool, uint256 fyTokenOut) external returns (uint256 baseIn, uint256 updateTime);

    function sellBasePreview(IPool pool, uint256 baseIn) external returns (uint256 fyTokenOut, uint256 updateTime);

    function sellFYTokenPreview(IPool pool, uint256 fyTokenIn) external returns (uint256 baseOut, uint256 updateTime);
}
