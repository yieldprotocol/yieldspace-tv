// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;
/*
   __     ___      _     _
   \ \   / (_)    | |   | | ██╗   ██╗██╗███████╗██╗     ██████╗ ███╗   ███╗ █████╗ ████████╗██╗  ██╗
    \ \_/ / _  ___| | __| | ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗████╗ ████║██╔══██╗╚══██╔══╝██║  ██║
     \   / | |/ _ \ |/ _` |  ╚████╔╝ ██║█████╗  ██║     ██║  ██║██╔████╔██║███████║   ██║   ███████║
      | |  | |  __/ | (_| |   ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║██║╚██╔╝██║██╔══██║   ██║   ██╔══██║
      |_|  |_|\___|_|\__,_|    ██║   ██║███████╗███████╗██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║
       yieldprotocol.com       ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
*/

import "forge-std/console.sol";
import {Cast} from "@yield-protocol/utils-v2/src/utils/Cast.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// Ethereum smart contract library implementing Yield Math model with yield bearing tokens.
library YieldMathS {
    using Cast for uint256;
    using Cast for uint128;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    error CAndMuMustBePositive();
    error GreaterThanFYTokenReserves();
    error RateUnderflow();
    error SumOverflow();
    error TMustBePositive();
    error TooFarFromMaturity();
    error TooManySharesIn();
    error Underflow();
    error UnderflowYXA();

    uint256 public constant WAD = 1e18;

    /* CORE FUNCTIONS
     ******************************************************************************************************************/

    /* ----------------------------------------------------------------------------------------------------------------
                                              ┌───────────────────────────────┐                    .-:::::::::::-.
      ┌──────────────┐                        │                               │                  .:::::::::::::::::.
      │$            $│                       \│                               │/                :  _______  __   __ :
      │ ┌────────────┴─┐                     \│                               │/               :: |       ||  | |  |::
      │ │$            $│                      │    fyTokenOutForSharesIn      │               ::: |    ___||  |_|  |:::
      │$│ ┌────────────┴─┐     ────────▶      │                               │  ────────▶    ::: |   |___ |       |:::
      └─┤ │$            $│                    │                               │               ::: |    ___||_     _|:::
        │$│  `sharesIn`  │                   /│                               │\              ::: |   |      |   |  :::
        └─┤              │                   /│                               │\               :: |___|      |___|  ::
          │$            $│                    │                      \(^o^)/  │                 :       ????        :
          └──────────────┘                    │                     YieldMath │                  `:::::::::::::::::'
                                              └───────────────────────────────┘                    `-:::::::::::-'
    */
    /// Calculates the amount of fyToken a user would get for given amount of shares.
    /// https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param sharesIn shares amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient,  e.g. 25 years in seconds
    /// @param g fee coefficient -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenOut the amount of fyToken a user would get for given amount of shares
    function fyTokenOutForSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesIn,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _fyTokenOutForSharesIn(sharesReserves, fyTokenReserves, sharesIn, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _fyTokenOutForSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesIn,
        uint256 a,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

        y = fyToken reserves
        z = shares reserves
        x = Δz (sharesIn)

                y - (                         sum                           )^(   invA   )
                y - ((    Za         ) + (  Ya  ) - (       Zxa           ) )^(   invA   )
        Δy = y - ( c/μ * (μz)^(1-t) +  y^(1-t) -  c/μ * (μz + μx)^(1-t)  )^(1 / (1 - t))

        */
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));

        // ya = fyTokenReserves ** a
        uint256 ya = _powHelper(fyTokenReserves, a);

        // normalizedSharesIn = μ * sharesIn
        uint256 normalizedSharesIn = mu.mulWadDown(sharesIn);

        // zx = normalizedSharesReserves + sharesIn * μ
        uint256 zx = normalizedSharesReserves + normalizedSharesIn;

        // zxa = c/μ * zx ** a
        uint256 zxa = c.divWadDown(mu).mulWadDown(_powHelper(zx, a));

        uint256 sum = za + ya - zxa;
        if (sum > (za + ya)) revert SumOverflow();

        // result = fyTokenReserves - (sum ** (1/a))
        uint256 fyTokenOut = fyTokenReserves - _powHelper(sum, WAD.divWadDown(a));
        if (fyTokenOut > fyTokenReserves) revert GreaterThanFYTokenReserves();

        return fyTokenOut;
    }

    /* ----------------------------------------------------------------------------------------------------------------
          .-:::::::::::-.                       ┌───────────────────────────────┐
        .:::::::::::::::::.                     │                               │
       :  _______  __   __ :                   \│                               │/              ┌──────────────┐
      :: |       ||  | |  |::                  \│                               │/              │$            $│
     ::: |    ___||  |_|  |:::                  │    sharesOutForFYTokenIn      │               │ ┌────────────┴─┐
     ::: |   |___ |       |:::   ────────▶      │                               │  ────────▶    │ │$            $│
     ::: |    ___||_     _|:::                  │                               │               │$│ ┌────────────┴─┐
     ::: |   |      |   |  :::                 /│                               │\              └─┤ │$            $│
      :: |___|      |___|  ::                  /│                               │\                │$│    SHARES    │
       :     `fyTokenIn`   :                    │                      \(^o^)/  │                 └─┤     ????     │
        `:::::::::::::::::'                     │                     YieldMath │                   │$            $│
          `-:::::::::::-'                       └───────────────────────────────┘                   └──────────────┘
    */
    /// Calculates the amount of shares a user would get for certain amount of fyToken.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param fyTokenIn fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient
    /// @param g fee coefficient
    /// @param c price of shares in terms of their base
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return amount of Shares a user would get for given amount of fyToken
    function sharesOutForFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenIn,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _sharesOutForFYTokenIn(sharesReserves, fyTokenReserves, fyTokenIn, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _sharesOutForFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenIn,
        uint256 a,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            y = fyToken reserves
            z = shares reserves
            x = Δy (fyTokenIn)

                 z - (                                rightTerm                                              )
                 z - (invMu) * (      Za              ) + ( Ya   ) - (    Yxa      ) / (c / μ) )^(   invA    )
            Δz = z -   1/μ   * ( ( (c / μ) * (μz)^(1-t) +  y^(1-t) - (y + x)^(1-t) ) / (c / μ) )^(1 / (1 - t))

        */

        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));

        // zaYaYxa = za + ya - yxa
        // ya = fyTokenReserves ** a
        // yxa = (fyTokenReserves + x) ** a   # x is aka Δy
        uint256 zaYaYxa = za + _powHelper(fyTokenReserves, a) - _powHelper(fyTokenReserves + fyTokenIn, a);

        uint256 rightTerm = (_powHelper(zaYaYxa.divWadDown(c.divWadDown(mu)), WAD.divWadDown(a))).divWadDown(mu);

        if (rightTerm > sharesReserves) revert RateUnderflow();

        return sharesReserves - rightTerm;
    }

    /* ----------------------------------------------------------------------------------------------------------------
          .-:::::::::::-.                       ┌───────────────────────────────┐
        .:::::::::::::::::.                     │                               │              ┌──────────────┐
       :  _______  __   __ :                   \│                               │/             │$            $│
      :: |       ||  | |  |::                  \│                               │/             │ ┌────────────┴─┐
     ::: |    ___||  |_|  |:::                  │    fyTokenInForSharesOut      │              │ │$            $│
     ::: |   |___ |       |:::   ────────▶      │                               │  ────────▶   │$│ ┌────────────┴─┐
     ::: |    ___||_     _|:::                  │                               │              └─┤ │$            $│
     ::: |   |      |   |  :::                 /│                               │\               │$│              │
      :: |___|      |___|  ::                  /│                               │\               └─┤  `sharesOut` │
       :        ????       :                    │                      \(^o^)/  │                  │$            $│
        `:::::::::::::::::'                     │                     YieldMath │                  └──────────────┘
          `-:::::::::::-'                       └───────────────────────────────┘
    */
    /// Calculates the amount of fyToken a user could sell for given amount of Shares.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param sharesOut Shares amount to be traded
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient
    /// @param g fee coefficient
    /// @param c price of shares in terms of their base
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenIn the amount of fyToken a user could sell for given amount of Shares
    function fyTokenInForSharesOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesOut,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _fyTokenInForSharesOut(sharesReserves, fyTokenReserves, sharesOut, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _fyTokenInForSharesOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 sharesOut,
        uint256 a,
        uint256 c,
        uint256 mu
    ) public pure returns (uint256) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            y = fyToken reserves
            z = shares reserves
            x = Δz (sharesOut)

                 (                  sum                                )^(   invA    ) - y
                 (    Za          ) + (  Ya  ) - (       Zxa           )^(   invA    ) - y
            Δy = ( c/μ * (μz)^(1-t) +  y^(1-t) - c/μ * (μz - μx)^(1-t) )^(1 / (1 - t)) - y

        */

        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));

        // ya = fyTokenReserves ** a
        uint256 ya = _powHelper(fyTokenReserves, a);

        // normalizedSharesOut = μ * sharesOut
        uint256 normalizedSharesOut = mu.mulWadDown(sharesOut);

        if (normalizedSharesOut > normalizedSharesReserves) revert TooManySharesIn();
        // zx = normalizedSharesReserves + sharesOut * μ
        uint256 zx = normalizedSharesReserves - normalizedSharesOut;

        // zxa = c/μ * zx ** a
        uint256 zxa = c.divWadDown(mu).mulWadDown(_powHelper(zx, a));

        uint256 sum = za + ya - zxa;

        // result = (sum ** (1/a)) - fyTokenReserves
        uint256 result = _powHelper(sum, WAD.divWadDown(a)) - fyTokenReserves;

        return result;
    }

    /* ----------------------------------------------------------------------------------------------------------------
                                              ┌───────────────────────────────┐                    .-:::::::::::-.
      ┌──────────────┐                        │                               │                  .:::::::::::::::::.
      │$            $│                       \│                               │/                :  _______  __   __ :
      │ ┌────────────┴─┐                     \│                               │/               :: |       ||  | |  |::
      │ │$            $│                      │    sharesInForFYTokenOut      │               ::: |    ___||  |_|  |:::
      │$│ ┌────────────┴─┐     ────────▶      │                               │  ────────▶    ::: |   |___ |       |:::
      └─┤ │$            $│                    │                               │               ::: |    ___||_     _|:::
        │$│    SHARES    │                   /│                               │\              ::: |   |      |   |  :::
        └─┤     ????     │                   /│                               │\               :: |___|      |___|  ::
          │$            $│                    │                      \(^o^)/  │                 :   `fyTokenOut`    :
          └──────────────┘                    │                     YieldMath │                  `:::::::::::::::::'
                                              └───────────────────────────────┘                    `-:::::::::::-'
    */
    /// Calculates the number of shares a user would have to pay for given amount of fyToken
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param fyTokenOut fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, e.g. 25 years in seconds
    /// @param g fee coefficient -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return result the amount of shares a user would have to pay for given amount of fyToken
    function sharesInForFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenOut,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        unchecked {
            if(c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _sharesInForFYTokenOut(sharesReserves, fyTokenReserves, fyTokenOut, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _sharesInForFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 fyTokenOut,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

        y = fyToken reserves
        z = shares reserves
        x = Δy (fyTokenOut)

             1/μ * (                 subtotal                            )^(   invA    ) - z
             1/μ * ((     Za       ) + (  Ya  ) - (    Yxa    )) / (c/μ) )^(   invA    ) - z
        Δz = 1/μ * (( c/μ * μz^(1-t) +  y^(1-t) - (y - x)^(1-t)) / (c/μ) )^(1 / (1 - t)) - z

        */
        unchecked {
            // za = c/μ * (normalizedSharesReserves ** a)
            uint256 za = c.divWadDown(mu).mulWadDown(
                _powHelper(mu.mulWadDown(sharesReserves.divWadDown(WAD)), a)
            );

            // ya = fyTokenReserves ** a
            uint256 ya = _powHelper(fyTokenReserves, a);

            // yxa = (fyTokenReserves - x) ** aß
            uint256 yxa = _powHelper(fyTokenReserves - fyTokenOut, a);
            if (fyTokenOut > fyTokenReserves) revert UnderflowYXA();

            uint256 zaYaYxa = (za + ya - yxa);

            // subtotal = (za + ya - yxa) / (c/μ)
            uint256 subtotal = WAD.divWadDown(mu).mulWadDown(
                _powHelper(zaYaYxa.divWadDown(c.divWadDown(mu)), WAD.divWadDown(a))
            );

            // result = (subtotal ** (1/a)) - sharesReserves
            uint256 result = subtotal - sharesReserves;
            if (result > subtotal) revert Underflow();

            return result;
        }
    }

    /// Calculates the max amount of fyToken a user could sell.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient,  e.g. 25 years in seconds
    /// @param g fee coefficient -- sb over 1.0 for buying shares from the pool
    /// @param c price of shares in terms of their base
    /// @return fyTokenIn the max amount of fyToken a user could sell
    function maxFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 fyTokenIn) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxFYTokenIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 fyTokenIn) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            Y = fyToken reserves
            Z = shares reserves
            y = maxFYTokenIn

                 (                  sum        )^(   invA    ) - Y
                 (    Za          ) + (  Ya  ) )^(   invA    ) - Y
            Δy = ( c/μ * (μz)^(1-t) +  Y^(1-t) )^(1 / (1 - t)) - Y

        */

        // normalizedSharesReserves = μ * sharesReserves
        uint256 normalizedSharesReserves = mu.mulWadDown(sharesReserves);

        // za = c/μ * (normalizedSharesReserves ** a)
        uint256 za = c.divWadDown(mu).mulWadDown(_powHelper(normalizedSharesReserves, a));

        // ya = fyTokenReserves ** a
        uint256 ya = _powHelper(fyTokenReserves, a);

        // sum = za + ya
        uint256 sum = za + ya;

        // result = (sum ** (1/a)) - fyTokenReserves
        fyTokenIn = _powHelper(sum, WAD.divWadDown(a)) - fyTokenReserves;
    }

    /// Calculates the max amount of fyToken a user could get.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient,  e.g. 25 years in seconds
    /// @param g fee coefficient -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return fyTokenOut the max amount of fyToken a user could get
    function maxFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 fyTokenOut) {
        unchecked {
            if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
            return _maxFYTokenOut(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
        }
    }

    function _maxFYTokenOut(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 fyTokenOut) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
            y = maxFyTokenOut
            Y = fyTokenReserves (virtual)
            Z = sharesReserves

                Y - ( (       numerator           ) / (  denominator  ) )^invA
                Y - ( ( (    Za      ) + (  Ya  ) ) / (  denominator  ) )^invA
            y = Y - ( (   c/μ * (μZ)^a +    Y^a   ) / (    c/μ + 1    ) )^(1/a)
        */

        // za = c/μ * ((μ * (sharesReserves / 1e18)) ** a)
        uint256 za = c.divWadDown(mu).mulWadDown(
            _powHelper(mu.mulWadDown(sharesReserves.divWadDown(WAD)), a)
        );

        // ya = (fyTokenReserves / 1e18) ** a
        uint256 ya = _powHelper(fyTokenReserves.divWadDown(WAD), a);

        // numerator = za + ya
        uint256 numerator = za + ya;

        // denominator = c/u + 1
        uint256 denominator = c.divWadDown(mu) + WAD;

        // rightTerm = (numerator / denominator) ** (1/a)
        uint256 rightTerm = _powHelper(numerator.divWadDown(denominator), WAD.divWadDown(a));

        // maxFYTokenOut_ = fyTokenReserves - (rightTerm * 1e18)
        fyTokenOut = fyTokenReserves - rightTerm.mulWadDown(WAD);
        if (fyTokenOut > fyTokenReserves) revert Underflow();
    }

    /// Calculates the max amount of base a user could sell.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return sharesIn Calculates the max amount of base a user could sell.
    function maxSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256 sharesIn) {
        if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();
        return _maxSharesIn(sharesReserves, fyTokenReserves, _computeA(timeTillMaturity, k, g), c, mu);
    }

    function _maxSharesIn(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 sharesIn) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
            y = maxSharesIn_
            Y = fyTokenReserves (virtual)
            Z = sharesReserves

                1/μ ( (       numerator           ) / (  denominator  ) )^invA  - Z
                1/μ ( ( (    Za      ) + (  Ya  ) ) / (  denominator  ) )^invA  - Z
            y = 1/μ ( ( c/μ * (μZ)^a   +    Y^a   ) / (     c/μ + 1   ) )^(1/a) - Z
        */

        // za = c/μ * ((μ * (sharesReserves / 1e18)) ** a)
        uint256 za = c.divWadDown(mu).mulWadDown(
            _powHelper(mu.mulWadDown(sharesReserves.divWadDown(WAD)), a)
        );

        // ya = (fyTokenReserves / 1e18) ** a
        uint256 ya = _powHelper(fyTokenReserves.divWadDown(WAD), a);

        // numerator za + ya
        uint256 numerator = za + ya;

        // denominator = c/μ + 1
        uint256 denominator = c.divWadDown(mu) + WAD;

        // leftTerm = 1/μ * (numerator / denominator) ** (1/a)
        uint256 leftTerm = WAD.divWadDown(mu).mulWadDown(
            _powHelper(numerator.divWadDown(denominator), WAD.divWadDown(a))
        );

        // result = (leftTerm * 1e18) - sharesReserves
        sharesIn = leftTerm.mulWadDown(WAD) - sharesReserves;
        if (sharesIn > leftTerm.mulWadDown(WAD)) revert Underflow();
    }

    /*
    This function is not needed as it's return value is driven directly by the shares liquidity of the pool

    https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?view#MaxSharesOut

    function maxSharesOut(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 maxSharesOut_) {} */

    /// Calculates the total supply invariant.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param totalSupply total supply
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, e.g. 25 years in seconds
    /// @param g fee coefficient -- use under 1.0 (g2)
    /// @param c price of shares in terms of their base
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return result Calculates the total supply invariant.
    function invariant(
        uint256 sharesReserves,
        uint256 fyTokenReserves,
        uint256 totalSupply,
        uint256 timeTillMaturity,
        uint256 k,
        uint256 g,
        uint256 c,
        uint256 mu
    ) external pure returns (uint256) {
        if (totalSupply == 0) return 0;
        if (c <= 0 || mu <= 0) revert CAndMuMustBePositive();

        return _invariant(sharesReserves, fyTokenReserves, totalSupply, _computeA(timeTillMaturity, k, g), c, mu);
    }

    function _invariant(
        uint256 sharesReserves, // z
        uint256 fyTokenReserves, // x
        uint256 totalSupply, // s
        uint256 a,
        uint256 c,
        uint256 mu
    ) internal pure returns (uint256 result) {
        unchecked {
            /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
                y = invariant
                Y = fyTokenReserves (virtual)
                Z = sharesReserves
                s = total supply

                    c/μ ( (       numerator           ) / (  denominator  ) )^invA  / s 
                    c/μ ( ( (    Za      ) + (  Ya  ) ) / (  denominator  ) )^invA  / s 
                y = c/μ ( ( c/μ * (μZ)^a   +    Y^a   ) / (     c/u + 1   ) )^(1/a) / s
            */

            // za = c/μ * ((μ * (sharesReserves / 1e18)) ** a)
            uint256 za = c.divWadDown(mu).mulWadDown(
                _powHelper(mu.mulWadDown(sharesReserves.divWadDown(WAD)), a)
            );

            // ya = (fyTokenReserves / 1e18) ** a
            uint256 ya = _powHelper(fyTokenReserves.divWadDown(WAD), a);

            // numerator = za + ya
            uint256 numerator = za + ya;

            // denominator = c/u + 1
            uint256 denominator = c.divWadDown(mu) + WAD;

            // topTerm = c/μ * (numerator / denominator) ** (1/a)
            uint256 topTerm = uint256(
                _powHelper(c.divWadDown(mu).mulWadDown(numerator.divWadDown(denominator)), WAD.divWadDown(a))
            );

            result = (topTerm.mulWadDown(WAD) * WAD) / totalSupply;
        }
    }

    /* UTILITY FUNCTIONS
     ******************************************************************************************************************/

    function _computeA(uint256 timeTillMaturity, uint256 k, uint256 g) internal pure returns (uint256) {
        // t = k * timeTillMaturity
        uint256 t = k * timeTillMaturity;
        if (t < 0) revert TMustBePositive();

        // a = (1 - gt)
        uint256 a = WAD - g.mulWadDown(t);
        if (a <= 0) revert TooFarFromMaturity();

        return a;
    }

    function _powHelper(uint256 x, uint256 y) internal pure returns (uint256 result) {
        x == 0 ? result = 0 : result = uint256(int256(x).powWad(int256(y)));
    }
}
