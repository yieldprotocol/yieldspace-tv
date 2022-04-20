// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

/* POOL ERRORS
******************************************************************************************************************/

/// The pool has matured and maybe you should too.
error AfterMaturity();

/// The pool has already been initialized. What are you thinking?
/// @dev To save gas, total supply == 0 is checked instead of a state variable
error Initialized();

/// Trade results in base balance > fyToken balance. We don't do that.
error InsufficientFYTokenBalance(uint128 newFYTokenBalance, uint128 newBaseBalance);

/// Represents the fee in bps, and it cannot be larger than 10,000.
/// @dev https://en.wikipedia.org/wiki/10,000 per wikipedia:
/// 10,000 (ten thousand) is the natural number following 9,999 and preceding 10,001.
/// @param proposedFee The fee that was proposed.
error InvalidFee(uint16 proposedFee);

/// The year is 2106 and an invalid maturity date was passed into the constructor.
/// Maturity date must be less than type(uint32).max
error MaturityOverflow();

/// Not enough base was found in the pool contract to complete the requested action. You just wasted gas.
/// @param baseAvailable The amount of unaccounted for base tokens.
/// @param baseNeeded The amount of base tokens required for the mint.
error NotEnoughBaseIn(uint256 baseAvailable, uint256 baseNeeded);

/// Not enough fYTokens were found in the pool contract to complete the requested action. :( smh
/// @param fYTokensAvailable The amount of unaccounted for fYTokens.
/// @param fYTokensNeeded The amount of fYToken tokens required for the mint.
error NotEnoughFYTokenIn(uint256 fYTokensAvailable, uint256 fYTokensNeeded);

/// The pool has not been initialized yet. INTRUDER ALERT!
/// @dev To save gas, total supply == 0 is checked instead of a state variable
error NotInitialized();

/// Mu is the initial c reading, usually obtained through an external call to the base contract. It cannot be zero.
/// If the current price of the base is really zero, you've got bigger problems.
error MuZero();

/// Maximum amount of fyToken (per the max arg) would be exceeded for the trade. gg
/// @param fyTokenIn fyTokens that would be required for the trade.
/// @param max The maximum amount of fyTokens to be paid as specified by the caller.
error SlippageDuringBuyBase(uint128 fyTokenIn, uint128 max);

/// The reserves have changed compared with the last cache which causes the burn to fall outside the bounds of min/max
/// slippage ratios selected. This is likely the result of a peanut butter sandwich attack.
/// @param newRatio The ratio that would have resulted from the mint.
/// @param minRatio The minimum ratio allowed as specified by the caller.
/// @param maxRatio The maximum ratio allowed as specified by the caller
error SlippageDuringBurn(uint256 newRatio, uint256 minRatio, uint256 maxRatio);


/// Maximium amount of base (per the max arg) was exceeded for the trade. L and ratio.
/// @param baseIn The base that would be required for the trade.
/// @param max The maximum amount of base to be paid as specified by the caller.
error SlippageDuringBuyFYToken(uint128 baseIn, uint128 max);

/// The reserves have changed compared with the last cache which causes the mint to fall outside the bounds of min/max
/// slippage ratios selected. This is likely the result of a bologna sandwich attack.
/// @param newRatio The ratio that would have resulted from the mint.
/// @param minRatio The minimum ratio allowed as specified by the caller.
/// @param maxRatio The maximum ratio allowed as specified by the caller
error SlippageDuringMint(uint256 newRatio, uint256 minRatio, uint256 maxRatio);

/// Minimum amount of fyToken (per the min arg) would not be met for the trade. Try again.
/// @param fyTokenOut fyTokens that would be obtained through the trade.
/// @param min The minimum amount of fyTokens as specified by the caller.
error SlippageDuringSellBase(uint128 fyTokenOut, uint128 min);


/// Minimum amount of base (per the min arg) would not be met for the trade. Come back later with more base.
/// @param baseOut bases that would be obtained through the trade.
/// @param min The minimum amount of bases as specified by the caller.
error SlippageDuringSellFYToken(uint128 baseOut, uint128 min);
