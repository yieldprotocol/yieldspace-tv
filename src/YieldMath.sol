// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./Math64x64.sol";
import "./Exp64x64.sol";

/**
 * Ethereum smart contract library implementing Yield Math model.
 */
library YieldMath {
  using Math64x64 for int128;
  using Math64x64 for uint128;
  using Math64x64 for int256;
  using Math64x64 for uint256;
  using Exp64x64 for uint128;

  uint128 public constant ONE = 0x10000000000000000; // In 64.64
  uint128 public constant TWO = 0x20000000000000000; // In 64.64
  uint256 public constant MAX = type(uint128).max;   // Used for overflow checks
  uint256 public constant VAR = 1e12;                // The logarithm math used is not precise to the wei, but can deviate up to 1e12 from the real value.

  /**
   * Calculate a YieldSpace pool invariant according to the whitepaper
   */
  function invariant(uint128 baseReserves, uint128 fyTokenReserves, uint256 totalSupply, uint128 timeTillMaturity, int128 ts)
      public pure returns(uint128)
  {
    if (totalSupply == 0) return 0;

    unchecked {
      // a = (1 - ts * timeTillMaturity)
      int128 a = int128(ONE).sub(ts.mul(timeTillMaturity.fromUInt()));
      require (a > 0, "YieldMath: Too far from maturity");

      uint256 sum =
      uint256(baseReserves.pow(uint128 (a), ONE)) +
      uint256(fyTokenReserves.pow(uint128 (a), ONE)) >> 1;
      require(sum < MAX, "YieldMath: Sum overflow");

      // We multiply the dividend by 1e18 to get a fixed point number with 18 decimals
      uint256 result = uint256(uint128(sum).pow(ONE, uint128(a))) * 1e18 / totalSupply;
      require (result < MAX, "YieldMath: Result overflow");

      return uint128(result);
    }
  }

  /**
   * Calculate the amount of fyToken a user would get for given amount of Base.
   * https://www.desmos.com/calculator/5nf2xuy6yb
   * @param baseReserves base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param baseAmount base amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of fyToken a user would get for given amount of Base
   */
  function fyTokenOutForBaseIn(
    uint128 baseReserves, uint128 fyTokenReserves, uint128 baseAmount,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns(uint128) {
    unchecked {
      uint128 a = _computeA(timeTillMaturity, ts, g);

      // za = baseReserves ** a
      uint256 za = baseReserves.pow(a, ONE);

      // ya = fyTokenReserves ** a
      uint256 ya = fyTokenReserves.pow(a, ONE);

      // zx = baseReserves + baseAmount
      uint256 zx = uint256(baseReserves) + uint256(baseAmount);
      require(zx <= MAX, "YieldMath: Too much base in");

      // zxa = zx ** a
      uint256 zxa = uint128(zx).pow(a, ONE);

      // sum = za + ya - zxa
      uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
      require(sum <= MAX, "YieldMath: Insufficient fyToken reserves");

      // result = fyTokenReserves - (sum ** (1/a))
      uint256 result = uint256(fyTokenReserves) - uint256(uint128(sum).pow(ONE, a));
      require(result <= MAX, "YieldMath: Rounding induced error");

      result = result > VAR ? result - VAR : 0; // Subtract error guard, flooring the result at zero

      return uint128(result);
    }
  }

  /**
   * Calculate the amount of base a user would get for certain amount of fyToken.
   * https://www.desmos.com/calculator/6jlrre7ybt
   * @param baseReserves base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param fyTokenAmount fyToken amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of Base a user would get for given amount of fyToken
   */
  function baseOutForFYTokenIn(
    uint128 baseReserves, uint128 fyTokenReserves, uint128 fyTokenAmount,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns(uint128) {
    unchecked {
      uint128 a = _computeA(timeTillMaturity, ts, g);

      // za = baseReserves ** a
      uint256 za = baseReserves.pow(a, ONE);

      // ya = fyTokenReserves ** a
      uint256 ya = fyTokenReserves.pow(a, ONE);

      // yx = fyDayReserves + fyTokenAmount
      uint256 yx = uint256(fyTokenReserves) + uint256(fyTokenAmount);
      require(yx <= MAX, "YieldMath: Too much fyToken in");

      // yxa = yx ** a
      uint256 yxa = uint128(yx).pow(a, ONE);

      // sum = za + ya - yxa
      uint256 sum = za + ya - yxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
      require(sum <= MAX, "YieldMath: Insufficient base reserves");

      // result = baseReserves - (sum ** (1/a))
      uint256 result = uint256(baseReserves) - uint256(uint128(sum).pow(ONE, a));
      require(result <= MAX, "YieldMath: Rounding induced error");

      result = result > VAR ? result - VAR : 0; // Subtract error guard, flooring the result at zero

      return uint128(result);
    }
  }

  /**
   * Calculate the amount of fyToken a user could sell for given amount of Base.
   * https://www.desmos.com/calculator/0rgnmtckvy
   * @param baseReserves base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param baseAmount Base amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of fyToken a user could sell for given amount of Base
   */
  function fyTokenInForBaseOut(
    uint128 baseReserves, uint128 fyTokenReserves, uint128 baseAmount,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns(uint128) {
    unchecked {
      uint128 a = _computeA(timeTillMaturity, ts, g);

      // za = baseReserves ** a
      uint256 za = baseReserves.pow(a, ONE);

      // ya = fyTokenReserves ** a
      uint256 ya = fyTokenReserves.pow(a, ONE);

      // zx = baseReserves - baseAmount
      uint256 zx = uint256(baseReserves) - uint256(baseAmount);
      require(zx <= MAX, "YieldMath: Too much base out");

      // zxa = zx ** a
      uint256 zxa = uint128(zx).pow(a, ONE);

      // sum = za + ya - zxa
      uint256 sum = za + ya - zxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
      require(sum <= MAX, "YieldMath: Resulting fyToken reserves too high");

      // result = (sum ** (1/a)) - fyTokenReserves
      uint256 result = uint256(uint128(sum).pow(ONE, a)) - uint256(fyTokenReserves);
      require(result <= MAX, "YieldMath: Rounding induced error");

      result = result < MAX - VAR ? result + VAR : MAX; // Add error guard, ceiling the result at max

      return uint128(result);
    }
  }

  /**
   * Calculate the amount of base a user would have to pay for certain amount of fyToken.
   * https://www.desmos.com/calculator/ws5oqj8x5i
   * @param baseReserves Base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param fyTokenAmount fyToken amount to be traded
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return the amount of base a user would have to pay for given amount of
   *         fyToken
   */
  function baseInForFYTokenOut(
    uint128 baseReserves, uint128 fyTokenReserves, uint128 fyTokenAmount,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns(uint128) {
    unchecked {
      uint128 a = _computeA(timeTillMaturity, ts, g);

      // za = baseReserves ** a
      uint256 za = baseReserves.pow(a, ONE);

      // ya = fyTokenReserves ** a
      uint256 ya = fyTokenReserves.pow(a, ONE);

      // yx = baseReserves - baseAmount
      uint256 yx = uint256(fyTokenReserves) - uint256(fyTokenAmount);
      require(yx <= MAX, "YieldMath: Too much fyToken out");

      // yxa = yx ** a
      uint256 yxa = uint128(yx).pow(a, ONE);

      // sum = za + ya - yxa
      uint256 sum = za + ya - yxa; // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
      require(sum <= MAX, "YieldMath: Resulting base reserves too high");

      // result = (sum ** (1/a)) - baseReserves
      uint256 result = uint256(uint128(sum).pow(ONE, a)) - uint256(baseReserves);
      require(result <= MAX, "YieldMath: Rounding induced error");

      result = result < MAX - VAR ? result + VAR : MAX; // Add error guard, ceiling the result at max

      return uint128(result);
    }
  }

  /**
   * Calculate the max amount of fyTokens that can be bought from the pool without making the interest rate negative.
   * See section 6.3 of the YieldSpace White paper
   * @param baseReserves Base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return max amount of fyTokens that can be bought from the pool
   */
  function maxFYTokenOut(
    uint128 baseReserves, uint128 fyTokenReserves,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns(uint128) {
    if (baseReserves == fyTokenReserves) return 0;
    unchecked {
      uint128 a = _computeA(timeTillMaturity, ts, g);

      // xa = baseReserves ** a
      uint128 xa = baseReserves.pow(a, ONE);

      // ya = fyTokenReserves ** a
      uint128 ya = fyTokenReserves.pow(a, ONE);

      int128 xy2 = (xa + ya).divu(TWO);

      uint inaccessible = uint256(uint128(xy2).pow(ONE, a));
      require(inaccessible <= MAX, "YieldMath: Rounding induced error");

      inaccessible = inaccessible < MAX - VAR ? inaccessible + VAR : MAX; // Add error guard, ceiling the result at max

      return uint128(inaccessible) > fyTokenReserves ? 0 : fyTokenReserves - uint128(inaccessible);
    }
  }

  /**
   * Calculate the max amount of fyTokens that can be sold to into the pool.
   * @param baseReserves Base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return max amount of fyTokens that can be sold to into the pool
   */
  function maxFYTokenIn(
    uint128 baseReserves, uint128 fyTokenReserves,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns(uint128) {
    unchecked {
      uint128 b = _computeB(timeTillMaturity, ts, g);

      // xa = baseReserves ** a
      uint128 xa = baseReserves.pow(b, ONE);

      // ya = fyTokenReserves ** a
      uint128 ya = fyTokenReserves.pow(b, ONE);

      uint result = (xa + ya).pow(ONE, b) - fyTokenReserves;
      require(result <= MAX, "YieldMath: Rounding induced error");

      result = result > VAR ? result - VAR : 0; // Subtract error guard, flooring the result at zero

      return uint128(result);
    }
  }

  /**
   * Calculate the max amount of base that can be sold to into the pool without making the interest rate negative.
   * @param baseReserves Base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return max amount of base that can be sold to into the pool
   */
  function maxBaseIn(
    uint128 baseReserves, uint128 fyTokenReserves,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns (uint128) {
    uint128 _maxFYTokenOut = maxFYTokenOut(baseReserves, fyTokenReserves, timeTillMaturity, ts, g);
    if (_maxFYTokenOut > 0)
      return baseInForFYTokenOut(baseReserves, fyTokenReserves, _maxFYTokenOut, timeTillMaturity, ts, g);
    return 0;
  }

  /**
   * Calculate the max amount of base that can be bought from the pool.
   * @param baseReserves Base reserves amount
   * @param fyTokenReserves fyToken reserves amount
   * @param timeTillMaturity time till maturity in seconds
   * @param ts time till maturity coefficient, multiplied by 2^64
   * @param g fee coefficient, multiplied by 2^64
   * @return max amount of base that can be bought from the pool
   */
  function maxBaseOut(
    uint128 baseReserves, uint128 fyTokenReserves,
    uint128 timeTillMaturity, int128 ts, int128 g)
  public pure returns (uint128) {
    uint128 _maxFYTokenIn = maxFYTokenIn(baseReserves, fyTokenReserves, timeTillMaturity, ts, g);
    return baseOutForFYTokenIn(baseReserves, fyTokenReserves, _maxFYTokenIn, timeTillMaturity, ts, g);
  }

  function _computeA(uint128 timeTillMaturity, int128 ts, int128 g) private pure returns (uint128) {
    unchecked {
      // t = ts * timeTillMaturity
      int128 t = ts.mul(timeTillMaturity.fromUInt());
      require(t >= 0, "YieldMath: t must be positive"); // Meaning neither T or ts can be negative

      // a = (1 - gt)
      int128 a = int128(ONE).sub(g.mul(t));
      require(a > 0, "YieldMath: Too far from maturity");
      require(a <= int128(ONE), "YieldMath: g must be positive");

      return uint128(a);
    }
  }

  function _computeB(uint128 timeTillMaturity, int128 ts, int128 g) private pure returns (uint128) {
    unchecked {
      // t = ts * timeTillMaturity
      int128 t = ts.mul(timeTillMaturity.fromUInt());
      require(t >= 0, "YieldMath: t must be positive"); // Meaning neither T or ts can be negative

      // b = (1 - t/g)
      int128 b = int128(ONE).sub(t.div(g));
      require(b > 0, "YieldMath: Too far from maturity");
      require(b <= int128(ONE), "YieldMath: g must be positive");

      return uint128(b);
    }
  }
}