// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

/* POOL EVENTS
 ******************************************************************************************************************/

interface PoolEvents {
    event FeesSet(uint16 g1Fee);
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
}
