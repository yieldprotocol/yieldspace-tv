// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./interfaces/IPool.sol";
import "./YieldMath.sol";


library YieldMathExtensions {

    /// @dev Calculate the invariant for this pool
    function invariant(IPool pool) external view returns (uint128) {
        uint32 maturity = pool.maturity();
        uint32 timeToMaturity = (maturity > uint32(block.timestamp)) ? maturity - uint32(block.timestamp) : 0;
        return YieldMath.invariant(
            pool.getBaseBalance(),
            pool.getFYTokenBalance(),
            pool.totalSupply(),
            timeToMaturity,
            pool.ts()
        );
    }
}
