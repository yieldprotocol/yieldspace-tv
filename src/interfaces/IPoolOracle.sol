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

    /// Returns how much fyToken would be required to buy `baseOut` base.
    /// @param baseOut Amount of base hypothetically desired.
    /// @return fyTokenIn Amount of fyToken hypothetically required.
    /// @return updateTime Timestamp for when this price was calculated.
    function buyBasePreview(IPool pool, uint256 baseOut) external returns (uint256 fyTokenIn, uint256 updateTime);

    /// Returns how much base would be required to buy `fyTokenOut`.
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @return baseIn Amount of base hypothetically required.
    /// @return updateTime Timestamp for when this price was calculated.
    function buyFYTokenPreview(IPool pool, uint256 fyTokenOut) external returns (uint256 baseIn, uint256 updateTime);

    /// Returns how much fyToken would be obtained by selling `baseIn`.
    /// @param baseIn Amount of base hypothetically sold.
    /// @return fyTokenOut Amount of fyToken hypothetically bought.
    /// @return updateTime Timestamp for when this price was calculated.
    function sellBasePreview(IPool pool, uint256 baseIn) external returns (uint256 fyTokenOut, uint256 updateTime);

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return baseOut Amount of base hypothetically bought.
    /// @return updateTime Timestamp for when this price was calculated.
    function sellFYTokenPreview(IPool pool, uint256 fyTokenIn) external returns (uint256 baseOut, uint256 updateTime);
}
