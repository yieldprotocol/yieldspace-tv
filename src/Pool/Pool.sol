// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "./PoolImports.sol"; /*

   __     ___      _     _
   \ \   / (_)    | |   | |  ██████╗  ██████╗  ██████╗ ██╗        ███████╗ ██████╗ ██╗
    \ \_/ / _  ___| | __| |  ██╔══██╗██╔═══██╗██╔═══██╗██║        ██╔════╝██╔═══██╗██║
     \   / | |/ _ \ |/ _` |  ██████╔╝██║   ██║██║   ██║██║        ███████╗██║   ██║██║
      | |  | |  __/ | (_| |  ██╔═══╝ ██║   ██║██║   ██║██║        ╚════██║██║   ██║██║
      |_|  |_|\___|_|\__,_|  ██║     ╚██████╔╝╚██████╔╝███████╗██╗███████║╚██████╔╝███████╗
       yieldprotocol.com     ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝╚══════╝ ╚═════╝ ╚══════╝

                                                ┌─────────┐
                                                │no       │
                                                │lifeguard│
                                                └─┬─────┬─┘       ==+
                    be cool, stay in pool         │     │    =======+
                                             _____│_____│______    |+
                                      \  .-'"___________________`-.|+
                                        ( .'"                   '-.)+
                                        |`-..__________________..-'|+
                                        |                          |+
             .-:::::::::::-.            |                          |+      ┌──────────────┐
           .:::::::::::::::::.          |         ---  ---         |+      │$            $│
          :  _______  __   __ :        .|         (o)  (o)         |+.     │ ┌────────────┴─┐
         :: |       ||  | |  |::      /`|                          |+'\    │ │$            $│
        ::: |    ___||  |_|  |:::    / /|            [             |+\ \   │$│ ┌────────────┴─┐
        ::: |   |___ |       |:::   / / |        ----------        |+ \ \  └─┤ │$  ERC4626   $│
        ::: |    ___||_     _|:::.-" ;  \        \________/        /+  \ "--/│$│  Tokenized   │
        ::: |   |      |   |  ::),.-'    `-..__________________..-' +=  `---=└─┤ Vault Shares │
         :: |___|      |___|  ::=/              |    | |    |                  │$            $│
          :       TOKEN       :                 |    | |    |                  └──────────────┘
           `:::::::::::::::::'                  |    | |    |
             `-:::::::::::-'                    +----+ +----+
                `'''''''`                  _..._|____| |____| _..._
                                         .` "-. `%   | |    %` .-" `.
                                        /      \    .: :.     /      \
                                        '-..___|_..=:` `-:=.._|___..-'
*/

/// A Yieldspace AMM implementation for pools which provide liquidity and trading of fyTokens vs base tokens.
/// **The base tokens in this implementation are ERC4626 compliant tokenized vault shares.**
/// See whitepaper and derived formulas: https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
/// @title  Pool.sol
/// @dev    Uses ABDK 64.64 mathlib for precision and reduced gas. Deploy pool with 4626 token and associated fyToken.
/// @author Adapted by @devtooligan from original work by @alcueca and UniswapV2. Maths and whitepaper by @aniemerg.
contract Pool is PoolEvents, IPoolTV, ERC20Permit, AccessControl {
    /* LIBRARIES
     *****************************************************************************************************************/

    using WDiv for uint256;
    using RDiv for uint256;
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using CastU128I128 for uint128;
    using CastU128U104 for uint128;
    using CastU256U104 for uint256;
    using CastU256U128 for uint256;
    using CastU256I256 for uint256;
    using MinimalTransferHelper for IFYToken;
    using MinimalTransferHelper for IERC20Like;

    /* MODIFIERS
     *****************************************************************************************************************/

    /// Trading can only be done before maturity.
    modifier beforeMaturity() {
        if (block.timestamp >= maturity) revert AfterMaturity();
        _;
    }

    /* IMMUTABLES
     *****************************************************************************************************************/

    /// This pool accepts a pair of ERC4626 base token and related fyToken.
    /// For most of this contract, only the ERC20 functionality of the base token is required.  As such, base is cast
    /// as an "IERC20Like" and only cast as an IERC4626 when that 4626 functionality is needed in _getBaseCurrentPrice()
    /// This wei, modules for non-4626 compliant base tokens can import this contract and override 4626 specific fn's.
    IERC20Like public immutable base;

    /// The underlying asset of the base (tokenized vault) token.
    /// It is an ERC20 token.
    IERC20Like public immutable baseUnderlyingAsset;

    /// The fyToken for the UNDERLYING asset of the base.  It's not fyYVDAI, it's still fyDAI.  Even though we hold base
    /// in this contract in a wrapped tokenized vault (e.g. Yearn Vault Dai), upon maturity, the fyToken is payable in
    /// the underlying asset of the fyToken and tokenized vault, not the tokenized vault token itself.
    IFYToken public immutable fyToken;

    /// The normalization coefficient, the initial c value or price per 1 share of base (64.64)
    int128 public immutable mu;

    /// Time stretch == 1 / seconds in 10 years (64.64)
    int128 public immutable ts;

    /// Pool's maturity date (not 64.64)
    uint32 public immutable maturity;

    /// Used to scale up to 18 decimals (not 64.64)
    uint96 public immutable scaleFactor;

    /* STRUCTS
     *****************************************************************************************************************/

    struct Cache {
        uint16 g1Fee;
        uint104 baseCached;
        uint104 fyTokenCached;
        uint32 blockTimestampLast;
    }

    /* STORAGE
     *****************************************************************************************************************/

    // The following 4 vars use one storage slot and can be retrieved in a Cache struct with getCache()

    /// This number is used to calculate the fees for buying/selling fyTokens.
    /// @dev This is a fp4 that represents a ratio out 1, where 1 is represented by 10000.
    uint16 public g1Fee;

    /// Base token reserves, cached.
    uint104 internal baseCached;

    /// fyToken reserves, cached.
    uint104 internal fyTokenCached;

    /// block.timestamp of last time reserve caches were updated.
    uint32 internal blockTimestampLast;

    /// cumulativeRatioLast
    /// A LAGGING, time weighted sum of the fyToken:base reserves ratio measured in ratio seconds.
    /// @dev Footgun 🔫 alert!  Be careful, this number is probably not what you need and it should normally be
    /// considered with blockTimestampLast. Use currentCumulativeRatio() for consumption as a TWAR observation.
    /// In future pools, this function's visibility may be changed to internal.
    /// @return a fixed point factor with 27 decimals (ray).
    uint256 public cumulativeRatioLast;


    /* CONSTRUCTOR
     *****************************************************************************************************************/
    constructor(
        address base_, //     address of base token
        address fyToken_, //  address of fyToken
        int128 ts_, //        time stretch(64.64)
        uint16 g1Fee_ //      fees (in bps) when buying fyToken
    )
        ERC20Permit(
            string(abi.encodePacked(IERC20Like(fyToken_).name(), " LP")),
            string(abi.encodePacked(IERC20Like(fyToken_).symbol(), "LP")),
            IERC20Like(fyToken_).decimals()
        )
    {
        /*  __   __        __  ___  __        __  ___  __   __
           /  ` /  \ |\ | /__`  |  |__) |  | /  `  |  /  \ |__)
           \__, \__/ | \| .__/  |  |  \ \__/ \__,  |  \__/ |  \ */

        if ((maturity = uint32(IFYToken(fyToken_).maturity())) > type(uint32).max) revert MaturityOverflow();
        // set immutables - initialize base and scale factor before calling _getC()
        uint256 decimals_ = IERC20Like(fyToken_).decimals();
        baseUnderlyingAsset = _getBaseUnderlyingAsset(base_);
        base = IERC20Like(base_);
        scaleFactor = uint96(10**(18 - uint96(decimals_))); // No more than 18 decimals allowed, reverts on underflow.

        mu = ((_getBaseCurrentPriceConstructor(base_) * uint96(10**(18 - uint96(decimals_))))).fromUInt().div(uint256(1e18).fromUInt());
        ts = ts_;
        fyToken = IFYToken(fyToken_);

        // set fee
        if (g1Fee_ > 10000) revert InvalidFee(g1Fee_);
        g1Fee = g1Fee_;
        emit FeesSet(g1Fee_);
    }

    /* LIQUIDITY FUNCTIONS

        ┌─────────────────────────────────────────────────┐
        │  mint, new life. gm!                            │
        │  buy, sell, mint more, trade, trade -- stop     │
        │  mature, burn. gg~                              │
        │                                                 │
        │ "Watashinojinsei (My Life)" - haiku by Poolie   │
        └─────────────────────────────────────────────────┘

     *****************************************************************************************************************/

    /*mint
                                                                                              v
         ___                                                                           \            /
         |_ \_/                   ┌───────────────────────────────┐
         |   |                    │                               │                 `    _......._     '   gm!
                                 \│                               │/                  .-:::::::::::-.
           │                     \│                               │/             `   :    __    ____ :   /
           └───────────────►      │            mint               │                 ::   / /   / __ \::
                                  │                               │  ──────▶    _   ::  / /   / /_/ /::   _
           ┌───────────────►      │                               │                 :: / /___/ ____/ ::
           │                     /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
         B A S E                  │                      \(^o^)/  │                   `-:::::::::::-'
    (underlying asset)            │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘
                                                                                       /            \
                                                                                              ^
    */
    /// Mint liquidity tokens in exchange for adding base and fyToken
    /// The amount of liquidity tokens to mint is calculated from the amount of unaccounted for fyToken in this contract.
    /// A proportional amount of base/underlyingAsset tokens need to be present in this contract, also unaccounted for.
    /// @dev _totalSupply > 0 check important here to prevent unauthorized initialization.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return tokensMinted The amount of LP tokens minted.
    function mint(
        address to,
        address remainder,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (_totalSupply == 0) revert NotInitialized();
        return _mint(to, remainder, 0, minRatio, maxRatio);
    }

    /// ╦┌┐┌┬┌┬┐┬┌─┐┬  ┬┌─┐┌─┐  ╔═╗┌─┐┌─┐┬
    /// ║││││ │ │├─┤│  │┌─┘├┤   ╠═╝│ ││ ││
    /// ╩┘└┘┴ ┴ ┴┴ ┴┴─┘┴└─┘└─┘  ╩  └─┘└─┘┴─┘
    /// @dev This is the exact same as mint() but with auth added and skip the supply > 0 check.
    /// This intialize mechanism is different than UniV2.  Tokens addresses are added at contract creation.
    /// This pool is considered initialized after the first LP token is minted.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return tokensMinted The amount of LP tokens minted.
    function init(
        address to,
        address remainder,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        auth
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 tokensMinted
        )
    {
        if (_totalSupply != 0) revert Initialized();
        (baseIn, fyTokenIn, tokensMinted) = _mint(to, remainder, 0, minRatio, maxRatio);
        emit gm();
    }

    /* mintWithBase
                                                                                             V
                                  ┌───────────────────────────────┐                   \            /
                                  │                               │                 `    _......._     '   gm!
                                 \│                               │/                  .-:::::::::::-.
                                 \│                               │/             `   :    __    ____ :   /
                                  │         mintWithBase          │                 ::   / /   / __ \::
         B A S E     ──────►      │                               │  ──────▶    _   ::  / /   / /_/ /::   _
     (underlying asset)           │                               │                 :: / /___/ ____/ ::
                                 /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
                                  │                      \(^o^)/  │                   `-:::::::::::-'
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘                    /           \
                                                                                            ^
    */
    /// Mint liquidity tokens in exchange for adding only base
    /// The amount of liquidity tokens is calculated from the amount of fyToken to buy from the pool.
    /// The base/underlying asset tokens need to be present in this contract, unaccounted for.
    /// @dev _totalSupply > 0 check important here to prevent unauthorized initialization.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return tokensMinted The amount of LP tokens minted.
    function mintWithBase(
        address to,
        address remainder,
        uint256 fyTokenToBuy,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (_totalSupply == 0) revert NotInitialized();
        return _mint(to, remainder, fyTokenToBuy, minRatio, maxRatio);
    }

    /// This is the internal function called by the external mint functions.
    /// Mint liquidity tokens, with an optional internal trade to buy fyToken beforehand.
    /// The amount of liquidity tokens is calculated from the amount of fyTokenToBuy from the pool,
    /// plus the amount of extra, unaccounted for fyToken in this contract.
    /// The base/underlying asset tokens also need to be present in this contract, unaccounted for.
    /// @dev Warning: This fn does not check if supply > 0 like the external functions do.
    /// This function overloads the ERC20._mint(address, uint) function.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return tokensMinted The amount of LP tokens minted.
    function _mint(
        address to,
        address remainder,
        uint256 fyTokenToBuy,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 tokensMinted
        )
    {
        // Wrap any underlying vault assets found in contract.
        _wrap(address(this));

        // Gather data
        uint256 supply = _totalSupply;
        Cache memory cache = _getCache();
        uint256 realFYTokenCached_ = cache.fyTokenCached - supply; // The fyToken cache includes the virtual fyToken, equal to the supply
        uint256 baseBalance = base.balanceOf(address(this));
        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                uint256(cache.baseCached).wdiv(realFYTokenCached_) < minRatio ||
                uint256(cache.baseCached).wdiv(realFYTokenCached_) > maxRatio
            ) revert SlippageDuringMint((uint256(cache.baseCached) * 1e18) / realFYTokenCached_, minRatio, maxRatio);
        }

        // Calculate token amounts
        if (supply == 0) {
            // **First mint**
            // Initialize at 1 pool token minted per base token supplied
            baseIn = baseBalance;
            tokensMinted = baseIn;
        } else if (realFYTokenCached_ == 0) {
            // Edge case, no fyToken in the Pool after initialization
            baseIn = baseBalance - cache.baseCached;
            tokensMinted = (supply * baseIn) / cache.baseCached;
        } else {
            // There is an optional virtual trade before the mint
            uint256 baseToSell;
            if (fyTokenToBuy != 0) {
                baseToSell = _buyFYTokenPreview(
                    fyTokenToBuy.u128(),
                    cache.baseCached,
                    cache.fyTokenCached,
                    _computeG1(cache.g1Fee)
                );
            }

            // We use all the available fyTokens, plus optional virtual trade. Surplus is in base tokens.
            fyTokenIn = fyToken.balanceOf(address(this)) - realFYTokenCached_;
            tokensMinted = (supply * (fyTokenToBuy + fyTokenIn)) / (realFYTokenCached_ - fyTokenToBuy);
            baseIn = baseToSell + ((cache.baseCached + baseToSell) * tokensMinted) / supply;
            if ((baseBalance - cache.baseCached) < baseIn) {
                revert NotEnoughBaseIn((baseBalance - cache.baseCached), baseIn);
            }
        }

        // Update TWAR
        _update(
            (cache.baseCached + baseIn).u128(),
            (cache.fyTokenCached + fyTokenIn + tokensMinted).u128(), // Include "virtual" fyToken from new minted LP tokens
            cache.baseCached,
            cache.fyTokenCached
        );

        // Execute mint
        _mint(to, tokensMinted);

        // Return any unused base tokens as underlying
        if (baseBalance > cache.baseCached + baseIn)
            // TODO: Consider unwrapping it directly to the user? Security issue?
            baseUnderlyingAsset.safeTransfer(remainder, _unwrap(address(this)));

        emit Liquidity(
            maturity,
            msg.sender,
            to,
            address(0),
            -(baseIn.i256()),
            -(fyTokenIn.i256()),
            tokensMinted.i256()
        );
    }

    /* burn
                        (   (
                        )    (
                   (  (|   (|  )
                )   )\/ ( \/(( (    gg            ___
                ((  /     ))\))))\      ┌~~~~~~►  |_ \_/
                 )\(          |  )      │         |   |
                /:  | __    ____/:      │
                ::   / /   / __ \::  ───┤
                ::  / /   / /_/ /::     │
                :: / /___/ ____/ ::     └~~~~~~►  B A S E underlying asset
                ::/_____/_/      ::
                 :               :
                  `-:::::::::::-'
                     `'''''''`
    */
    /// Burn liquidity tokens in exchange for base and fyToken.
    /// The liquidity tokens need to be in this contract.
    /// @param baseTo Wallet receiving the base.
    /// @param fyTokenTo Wallet receiving the fyToken.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of LP tokens burned.
    /// @return The amount of base tokens received.
    /// @return The amount of fyTokens received.
    function burn(
        address baseTo,
        address fyTokenTo,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _burn(baseTo, fyTokenTo, false, minRatio, maxRatio);
    }

    /* burnForBase

                        (   (
                        )    (
                    (  (|   (|  )
                 )   )\/ ( \/(( (    gg
                 ((  /     ))\))))\
                  )\(          |  )
                /:  | __    ____/:
                ::   / /   / __ \::   ~~~~~~~►   B A S E underlying asset
                ::  / /   / /_/ /::
                :: / /___/ ____/ ::
                ::/_____/_/      ::
                 :               :
                  `-:::::::::::-'
                     `'''''''`
    */
    /// Burn liquidity tokens in exchange for base.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param to Wallet receiving the base and fyToken.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return lpTokensBurned The amount of lp tokens burned.
    /// @return baseOut The amount of base tokens returned.
    function burnForBase(
        address to,
        uint256 minRatio,
        uint256 maxRatio
    ) external virtual override returns (uint256 lpTokensBurned, uint256 baseOut) {
        (lpTokensBurned, baseOut, ) = _burn(to, address(0), true, minRatio, maxRatio);
    }

    /// Burn liquidity tokens in exchange for base/underlying asset.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @dev This function overloads the ERC20._burn(address, uint) function.
    /// @param baseTo Wallet receiving the base.
    /// @param fyTokenTo Wallet receiving the fyToken.
    /// @param tradeToBase Whether the resulting fyToken should be traded for base tokens.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return lpTokensBurned The amount of pool tokens burned.
    /// @return baseOut The amount of base tokens returned.
    /// @return fyTokenOut The amount of fyTokens returned.
    function _burn(
        address baseTo,
        address fyTokenTo,
        bool tradeToBase,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        returns (
            uint256 lpTokensBurned,
            uint256 baseOut,
            uint256 fyTokenOut
        )
    {
        // Gather data
        lpTokensBurned = _balanceOf[address(this)];
        uint256 supply = _totalSupply;

        Cache memory cache = _getCache();
        uint96 scaleFactor_ = scaleFactor;

        uint256 realFYTokenCached_ = cache.fyTokenCached - supply; // The fyToken cache includes the virtual fyToken, equal to the supply
        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                (uint256(cache.baseCached).wdiv(realFYTokenCached_) < minRatio) ||
                (uint256(cache.baseCached).wdiv(realFYTokenCached_) > maxRatio)
            ) {
                revert SlippageDuringBurn(uint256(cache.baseCached).wdiv(realFYTokenCached_), minRatio, maxRatio);
            }
        }
        // Calculate trade
        baseOut = (lpTokensBurned * cache.baseCached) / supply;
        fyTokenOut = (lpTokensBurned * realFYTokenCached_) / supply;

        if (tradeToBase) {
            baseOut +=
                YieldMath.sharesOutForFYTokenIn( //                                This is a virtual sell
                    (cache.baseCached - baseOut.u128()) * scaleFactor_, //        Cache, minus virtual burn
                    (cache.fyTokenCached - fyTokenOut.u128()) * scaleFactor_, //  Cache, minus virtual burn
                    fyTokenOut.u128() * scaleFactor_, //                          Sell the virtual fyToken obtained
                    maturity - uint32(block.timestamp), //                         This can't be called after maturity
                    ts,
                    _computeG2(cache.g1Fee),
                    _getC(),
                    mu
                ) /
                scaleFactor_;
            fyTokenOut = 0;
        }
        // Update TWAR
        _update(
            (cache.baseCached - baseOut).u128(),
            (cache.fyTokenCached - fyTokenOut - lpTokensBurned).u128(),
            cache.baseCached,
            cache.fyTokenCached
        );
        // Transfer assets
        _burn(address(this), lpTokensBurned); // This is calling the actual ERC20 _burn.

        // TODO: Consider unwrapping it directly to the user? Security issue?
        baseUnderlyingAsset.safeTransfer(baseTo, _unwrap(address(this)));

        if (fyTokenOut != 0) fyToken.safeTransfer(fyTokenTo, fyTokenOut);

        emit Liquidity(
            maturity,
            msg.sender,
            baseTo,
            fyTokenTo,
            baseOut.i256(),
            fyTokenOut.i256(),
            -(lpTokensBurned.i256())
        );

        if (supply == lpTokensBurned && block.timestamp >= maturity) {
            emit gg();
        }
    }

    /* TRADING FUNCTIONS
     ****************************************************************************************************************/

    /* buyBase

                         I want to buy `uint128 baseOut` worth of base underlying asset tokens.
             _______     I've transferred you some fyTokens -- that should be enough.
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|::      ok guy      │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :                   :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__GG__|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │   baseOut    │\.-" ;  \        \________/        /+
              |  |  |              │$            $│),.-'    `-..__________________..-' +=
              |  |  |              └──────────────┘                |    | |    |
              (  (  |                                              |    | |    |
              |  |  |                                              |    | |    |
              |  |  |                                              T----T T----T
             _|  |  |                                         _..._L____J L____J _..._
            (_____[__)                                      .` "-. `%   | |    %` .-" `.
                                                           /      \    .: :.     /      \
                                                           '-..___|_..=:` `-:=.._|___..-'
    */
    /// Buy base with fyToken
    /// The trader needs to have transferred in the correct amount of fyTokens in advance.
    /// @param to Wallet receiving the base being bought.
    /// @param baseOut Amount of base being bought that will be deposited in `to` wallet.
    /// @param max Maximum amount of fyToken that will be paid for the trade.
    /// @return fyTokenIn Amount of fyToken that will be taken from caller.
    function buyBase(
        address to,
        uint128 baseOut,
        uint128 max
    ) external virtual override returns (uint128 fyTokenIn) {
        // Calculate trade and cache values
        uint128 fyTokenBalance = _getFYTokenBalance();
        Cache memory cache = _getCache();
        fyTokenIn = _buyBasePreview(baseOut, cache.baseCached, cache.fyTokenCached, _computeG2(cache.g1Fee));

        // Checks
        if (fyTokenBalance - cache.fyTokenCached < fyTokenIn) {
            revert NotEnoughFYTokenIn(fyTokenBalance - cache.fyTokenCached, fyTokenIn);
        }
        if (fyTokenIn > max) revert SlippageDuringBuyBase(fyTokenIn, max);

        // Update TWAR
        _update(cache.baseCached - baseOut, cache.fyTokenCached + fyTokenIn, cache.baseCached, cache.fyTokenCached);

        // Transfer assets
        // TODO: Consider unwrapping it directly to the user? Security issue?
        baseUnderlyingAsset.safeTransfer(to, _unwrap(address(this)));

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
    }

    /// Returns how much fyToken would be required to buy `baseOut` base.
    /// @param baseOut Amount of base hypothetically desired.
    /// @return Amount of fyToken hypothetically required.
    function buyBasePreview(uint128 baseOut) external view virtual override returns (uint128) {
        Cache memory cache = _getCache();
        return _buyBasePreview(baseOut, cache.baseCached, cache.fyTokenCached, _computeG2(cache.g1Fee));
    }

    /// Returns how much fyToken would be required to buy `baseOut` base.
    function _buyBasePreview(
        uint128 baseOut,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) internal view beforeMaturity returns (uint128) {
        uint96 scaleFactor_ = scaleFactor;
        return
            YieldMath.fyTokenInForSharesOut(
                baseBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                baseOut * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) / scaleFactor_;
    }

    /*buyFYToken

                         I want to buy `uint128 fyTokenOut` worth of fyTokens.
             _______     I've transferred you some base/underlying tokens -- that should be enough.
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│   hmm, let's see here     │     │    =======+
        \  \   \ == /      │ │   B A S E    │                      _____│_____│______    |+
         \  \___|  |___    │$│  underlying  │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$   asset    $│                 ( .'"                   '-.)+
           \            \    └──────────────┘                 |`-..__________________..-'|+
            --|  GUY |\_/\  / /                               |                          |+
              |      | \  \/ /                                |                          |+
              |      |  \   /         _......._             /`|       ---     ---        |+
              |      |   \_/       .-:::::::::::-.         / /|       (o )    (o )       |+
              |______|           .:::::::::::::::::.      / / |                          |+
              |__GG__|          :  _______  __   __ : _.-" ;  |            [             |+
              |      |         :: |       ||  | |  |::),.-'   |        ----------        |+
              |  |   |        ::: |    ___||  |_|  |:::/      \        \________/        /+
              |  |  _|        ::: |   |___ |       |:::        `-..__________________..-' +=
              |  |  |         ::: |    ___||_     _|:::               |    | |    |
              |  |  |         ::: |   |      |   |  :::               |    | |    |
              (  (  |          :: |___|      |___|  ::                |    | |    |
              |  |  |           :     fyTokenOut    :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
    */
    /// Buy fyToken with base/underlying asset
    /// The trader needs to have transferred in the correct amount of tokens in advance.
    /// @param to Wallet receiving the fyToken being bought.
    /// @param fyTokenOut Amount of fyToken being bought that will be deposited in `to` wallet.
    /// @param max Maximum amount of base token that will be paid for the trade.
    /// @return baseIn Amount of base that will be taken from caller's wallet.
    function buyFYToken(
        address to,
        uint128 fyTokenOut,
        uint128 max
    ) external virtual override returns (uint128 baseIn) {
        // Wrap any base underlying assets found in contract.
        _wrap(address(this));

        // Calculate trade
        uint128 baseBalance = _getBaseBalance();
        Cache memory cache = _getCache();
        baseIn = _buyFYTokenPreview(fyTokenOut, cache.baseCached, cache.fyTokenCached, _computeG1(cache.g1Fee));

        // Checks
        if (baseBalance - cache.baseCached < baseIn) revert NotEnoughBaseIn((baseBalance - cache.baseCached), baseIn);
        if (baseIn > max) revert SlippageDuringBuyFYToken(baseIn, max);

        // Update TWAR
        _update(cache.baseCached + baseIn, cache.fyTokenCached - fyTokenOut, cache.baseCached, cache.fyTokenCached);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @return Amount of base hypothetically required.
    function buyFYTokenPreview(uint128 fyTokenOut) external view virtual override returns (uint128) {
        Cache memory cache = _getCache();
        return _buyFYTokenPreview(fyTokenOut, cache.baseCached, cache.fyTokenCached, _computeG1(cache.g1Fee));
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    function _buyFYTokenPreview(
        uint128 fyTokenOut,
        uint128 baseBalance,
        uint128 fyTokenBalance,
        int128 g1_
    ) internal view beforeMaturity returns (uint128 baseIn) {
        uint96 scaleFactor_ = scaleFactor;

        baseIn =
            YieldMath.sharesInForFYTokenOut(
                baseBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                fyTokenOut * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g1_,
                _getC(),
                mu
            ) /
            scaleFactor_;

        if ((fyTokenBalance - fyTokenOut) < (baseBalance + baseIn)) {
            revert InsufficientFYTokenBalance(fyTokenBalance - fyTokenOut, baseBalance + baseIn);
        }
    }

    /* sellBase

                         I've transfered you some base tokens.
             _______     Can you swap them for fyTokens?
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│             can           │     │    =======+
        \  \   \ == /      │ │              │                      _____│_____│______    |+
         \  \___|  |___    │$│    baseIn    │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$            $│                 ( .'"                   '-.)+
           \            \   ( └──────────────┘                 |`-..__________________..-'|+
            --|  GUY |\_/\  / /                               |                          |+
              |      | \  \/ /                                |                          |+
              |      |  \   /         _......._             /`|       ---     ---        |+
              |      |   \_/       .-:::::::::::-.         / /|       (o )    (o )       |+
              |______|           .:::::::::::::::::.      / / |                          |+
              |__GG__|          :  _______  __   __ : _.-" ;  |            [             |+
              |      |         :: |       ||  | |  |::),.-'   |        ----------        |+
              |  |   |        ::: |    ___||  |_|  |:::/      \        \________/        /+
              |  |  _|        ::: |   |___ |       |:::        `-..__________________..-' +=
              |  |  |         ::: |    ___||_     _|:::               |    | |    |
              |  |  |         ::: |   |      |   |  :::               |    | |    |
              (  (  |          :: |___|      |___|  ::                |    | |    |
              |  |  |           :      ????         :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
    */
    /// Sell base for fyToken.
    /// The trader needs to have transferred the amount of base/underlying to sell to the pool before calling this fn.
    /// @param to Wallet receiving the fyToken being bought.
    /// @param min Minimum accepted amount of fyToken.
    /// @return fyTokenOut Amount of fyToken that will be deposited on `to` wallet.
    function sellBase(address to, uint128 min) external virtual override returns (uint128 fyTokenOut) {
        // Wrap any underlying vault assets found in contract.
        _wrap(address(this));

        // Calculate trade
        Cache memory cache = _getCache();
        uint104 baseBalance = _getBaseBalance();
        uint128 baseIn = baseBalance - cache.baseCached;
        fyTokenOut = _sellBasePreview(baseIn, cache.baseCached, cache.fyTokenCached, _computeG1(cache.g1Fee));

        // Check slippage
        if (fyTokenOut < min) revert SlippageDuringSellBase(fyTokenOut, min);

        // Update TWAR
        _update(baseBalance, cache.fyTokenCached - fyTokenOut, cache.baseCached, cache.fyTokenCached);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    /// @param baseIn Amount of base hypothetically sold.
    /// @return Amount of fyToken hypothetically bought.
    function sellBasePreview(uint128 baseIn) external view virtual override returns (uint128) {
        Cache memory cache = _getCache();
        return _sellBasePreview(baseIn, cache.baseCached, cache.fyTokenCached, _computeG1(cache.g1Fee));
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    function _sellBasePreview(
        uint128 baseIn,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g1_
    ) internal view beforeMaturity returns (uint128 fyTokenOut) {
        uint96 scaleFactor_ = scaleFactor;

        fyTokenOut =
            YieldMath.fyTokenOutForSharesIn(
                baseBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                baseIn * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g1_,
                _getC(),
                mu
            ) /
            scaleFactor_;

        if (fyTokenBalance - fyTokenOut < baseBalance + baseIn) {
            revert InsufficientFYTokenBalance(fyTokenBalance - fyTokenOut, baseBalance + baseIn);
        }
    }

    /*sellFYToken
                         I've transferred you some fyTokens.
             _______     Can you swap them for base?
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|:::     lfg         │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :      fyTokenIn    :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__GG__|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │    ????      │\.-" ;  \        \________/        /+
              |  |  |              │$            $│),.-'    `-..__________________..-' +=
              |  |  |              └──────────────┘                |    | |    |
              (  (  |                                              |    | |    |
              |  |  |                                              |    | |    |
              |  |  |                                              T----T T----T
             _|  |  |                                         _..._L____J L____J _..._
            (_____[__)                                      .` "-. `%   | |    %` .-" `.
                                                           /      \    .: :.     /      \
                                                           '-..___|_..=:` `-:=.._|___..-'
    */
    /// Sell fyToken for base
    /// The trader needs to have transferred the amount of fyToken to sell to the pool before in the same transaction.
    /// @param to Wallet receiving the base being bought.
    /// @param min Minimum accepted amount of base.
    /// @return baseOut Amount of base that will be deposited on `to` wallet.
    function sellFYToken(address to, uint128 min) external virtual override returns (uint128 baseOut) {
        // Calculate trade
        Cache memory cache = _getCache();
        uint104 fyTokenBalance = _getFYTokenBalance();
        uint128 fyTokenIn = fyTokenBalance - cache.fyTokenCached;
        baseOut = _sellFYTokenPreview(fyTokenIn, cache.baseCached, cache.fyTokenCached, _computeG2(cache.g1Fee));

        // Check slippage
        if (baseOut < min) revert SlippageDuringSellFYToken(baseOut, min);

        // Update TWAR
        _update(cache.baseCached - baseOut, fyTokenBalance, cache.baseCached, cache.fyTokenCached);

        // Transfer assets
        // TODO: Consider unwrapping it directly to the user? Security issue?
        baseUnderlyingAsset.safeTransfer(to, _unwrap(address(this)));

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return Amount of base hypothetically bought.
    function sellFYTokenPreview(uint128 fyTokenIn) public view virtual returns (uint128) {
        Cache memory cache = _getCache();
        return _sellFYTokenPreview(fyTokenIn, cache.baseCached, cache.fyTokenCached, _computeG2(cache.g1Fee));
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    function _sellFYTokenPreview(
        uint128 fyTokenIn,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) internal view beforeMaturity returns (uint128) {
        uint96 scaleFactor_ = scaleFactor;

        return
            YieldMath.sharesOutForFYTokenIn(
                baseBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                fyTokenIn * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) / scaleFactor_;
    }

    /* WRAPPING FUNCTIONS
     ****************************************************************************************************************/

    /// Wraps any underlying asset tokens found in the contract, converting them to base tokenized vault shares.
    /// @dev This is provided as a convenience and uses the 4626 deposit method.
    /// @param receiver The address to which the wrapped tokens will be sent.
    /// @return shares The amount of wrapped tokens sent to the receiver.
    function wrap(address receiver) external returns (uint256 shares) {
        shares = _wrap(receiver);
    }

    /// Internal function for wrapping underlying asset tokens.  This should be overridden by modules.
    /// It wraps the entire balance of the underlying found in this contract.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual returns (uint256 shares) {
        shares = IERC4626(address(base)).deposit(baseUnderlyingAsset.balanceOf(address(this)), receiver);
    }

    /// Unwraps base shares found unaccounted for in this contract, converting them to the underlying asset assets.
    /// @dev This is provided as a convenience and uses the 4626 redeem method.
    /// @param receiver The address to which the assets will be sent.
    /// @return assets The amount of asset tokens sent to the receiver.
    function unwrap(address receiver) external returns (uint256 assets) {
        assets = _unwrap(receiver);
    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// @dev This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return assets The amount of underlying asset assets sent to the receiver.
    function _unwrap(address receiver) internal virtual returns (uint256 assets) {
        uint256 surplus = _getBaseBalance() - baseCached;

        // The third param of the 4626 redeem fn, `owner`, is always this contract address.
        assets = IERC4626(address(base)).redeem(surplus, receiver, address(this));
    }

    /// This is used by the constructor to set the base's underlying asset as immutable.
    /// This should be overridden by modules.
    /// @dev We use the IERC20Like interface, but this should be an ERC20 asset per EIP4626.
    function _getBaseUnderlyingAsset(address base_) internal virtual returns (IERC20Like) {
        return IERC20Like(address(IERC4626(base_).asset()));
    }

    /* BALANCES MANAGEMENT AND ADMINISTRATIVE FUNCTIONS
       Note: The sync() function has been discontinued and removed.
     *****************************************************************************************************************/
    /*
                  _____________________________________
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   ||_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_||
                   || | | | | | | | | | | | | | | | ||
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                  _|o_o_o_o_o_o_o_o_o_o_o_o_o_o_o_o_o|_
                          "Poolie's Abacus" - ejm */

    /// Calculates cumulative ratio as of current timestamp.  Can be consumed for TWAR observations.
    /// @dev See UniV2 implmentation: https://tinyurl.com/UniV2currentCumulativePrice
    /// @return currentCumulativeRatio_ is the cumulative ratio up to the current timestamp as ray.
    /// @return blockTimestampCurrent is the current block timestamp that the currentCumulativeRatio was computed with.
    function currentCumulativeRatio()
        external
        view
        virtual
        returns (uint256 currentCumulativeRatio_, uint256 blockTimestampCurrent)
    {
        blockTimestampCurrent = block.timestamp;
        uint256 timeElapsed;
        unchecked {
            timeElapsed = blockTimestampCurrent - blockTimestampLast;
        }

        // Multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
        currentCumulativeRatio_ = cumulativeRatioLast + (fyTokenCached * timeElapsed).rdiv(baseCached);
    }

    /// Update cached values and, on the first call per block, cumulativeRatioLast.
    /// cumulativeRatioLast is a LAGGING, time weighted sum of the reserves ratio which is updated as follows:
    ///
    ///   cumulativeRatioLast += old fyTokenReserves / old baseReserves * seconds elapsed since blockTimestampLast
    ///
    /// Example:
    ///   First mint creates a ratio of 1:1.
    ///   300 seconds later a trade occurs:
    ///     - cumulativeRatioLast is updated: 0 + 1/1 * 300 == 300
    ///     - baseCached and fyTokenCached are updated with the new reserves amounts.
    ///     - This causes the ratio to skew to 1.1 / 1.
    ///   200 seconds later another trade occurs:
    ///     - NOTE: During this 200 seconds, cumulativeRatioLast == 300, which represents the "last" updated amount.
    ///     - cumulativeRatioLast is updated: 300 + 1.1 / 1 * 200 == 520
    ///     - baseCached and fyTokenCached updated accordingly...etc.
    ///
    /// @dev See UniV2 implmentation: https://tinyurl.com/UniV2UpdateCumulativePrice
    function _update(
        uint128 baseBalance,
        uint128 fyBalance,
        uint104 baseCached_,
        uint104 fyTokenCached_
    ) internal {
        // No need to update and spend gas on SSTORE if reserves haven't changed.
        if (baseBalance == baseCached_ && fyBalance == fyTokenCached_) return;

        uint32 blockTimestamp = uint32(block.timestamp);
        uint32 timeElapsed;
        timeElapsed = blockTimestamp - blockTimestampLast; // reverts on underflow

        uint256 oldCumulativeRatioLast = cumulativeRatioLast;
        uint256 newCumulativeRatioLast = oldCumulativeRatioLast;
        if (timeElapsed > 0 && fyTokenCached_ > 0 && baseCached_ > 0) {
            // Multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
            uint256 scaledFYTokenCached = uint256(fyTokenCached_) * 1e27;
            newCumulativeRatioLast += (scaledFYTokenCached * timeElapsed) / baseCached_;
        }

        blockTimestampLast = blockTimestamp;
        cumulativeRatioLast = newCumulativeRatioLast;

        // Update the reserves caches
        uint104 newBaseCached = baseBalance.u104();
        uint104 newFYTokenCached = fyBalance.u104();
        baseCached = newBaseCached;
        fyTokenCached = newFYTokenCached;

        emit Sync(newBaseCached, newFYTokenCached, newCumulativeRatioLast);
    }

    /// Exposes the 64.64 factor used for determining fees.
    /// A value of 1 means no fees.  Here g1 < 1 because it is used when selling base shares to the pool.
    /// Useful for external contracts that need to perform calculations related to pool.
    /// @dev Converts state var cache.g1Fee(fp4) to a 64bit divided by 10,000
    /// @return a 64bit factor used for applying fees when buying fyToken/selling base.
    function g1() external view returns (int128) {
        Cache memory cache = _getCache();
        return _computeG1(cache.g1Fee);
    }

    /// Returns the ratio of net proceeds after fees, for buying fyToken
    function _computeG1(uint16 g1Fee_) internal pure returns (int128) {
        return uint256(g1Fee_).fromUInt().div(uint256(10000).fromUInt());
    }

    /// Exposes the 64.64 factor used for determining fees.
    /// A value of 1 means no fees.  Here g2 > 1 because it is used when selling fyToken to the pool.
    /// Useful for external contracts that need to perform calculations related to pool.
    /// @dev Calculated by dividing 10,000 by state var cache.g1Fee(fp4) and converting to 64bit.
    /// @return a 64bit factor used for applying fees when selling fyToken/buying base.
    function g2() external view returns (int128) {
        Cache memory cache = _getCache();
        return _computeG2(cache.g1Fee);
    }

    /// Returns the ratio of net proceeds after fees, for selling fyToken
    function _computeG2(uint16 g1Fee_) internal pure returns (int128) {
        // Divide 1 (64.64) by g1
        return int128(YieldMath.ONE).div(uint256(g1Fee_).fromUInt().div(uint256(10000).fromUInt()));
    }

    /// Returns the base balance.
    /// @return The current balance of the pool's base tokens.
    function getBaseBalance() public view virtual override returns (uint104) {
        return _getBaseBalance();
    }

    /// Returns the base balance
    function _getBaseBalance() internal view returns (uint104) {
        return base.balanceOf(address(this)).u104();
    }

    /// Returns the base token current price.
    /// @return The price of 1 share of a tokenized vault token in terms of its underlying asset cast as uint256.
    function getBaseCurrentPrice() external view returns (uint256) {
        return _getBaseCurrentPrice();
    }

    /// Returns the base token current price.
    /// @dev This assumes the shares, base, and lp tokens all use the same decimals.
    /// This function should be overriden by modules.
    /// @return The price of 1 share of a tokenized vault token in terms of its underlying cast as uint256.
    function _getBaseCurrentPrice() internal view virtual returns (uint256) {
        return IERC4626(address(base)).convertToAssets(10**base.decimals());
    }

    /// Returns the base token current price.
    /// @dev This fn is called from the constructor and avoids the use of unitialized immutables.
    /// This function should be overriden by modules.
    /// @return The price of 1 share of a tokenized vault token in terms of its underlying cast as uint256.
    function _getBaseCurrentPriceConstructor(address base_) internal view virtual returns (uint256) {
        return IERC4626(base_).convertToAssets(10**IERC20Like(base_).decimals());
    }

    /// Returns current price of 1 share in 64bit.
    /// Useful for external contracts that need to perform calculations related to pool.
    /// @return The current price (as determined by the token) scalled to 18 digits and converted to 64.64.
    function getC() external view returns (int128) {
        return _getC();
    }

    /// Returns the c based on the current price
    function _getC() internal view returns (int128) {
        return ((_getBaseCurrentPrice() * scaleFactor)).fromUInt().div(uint256(1e18).fromUInt());
    }

    /// Returns the all storage vars except for cumulativeRatioLast
    /// @return g1Fee  This is a fp4 number where 10_000 is 1.
    /// @return Cached base token balance.
    /// @return Cached virtual FY token balance which is the actual balance plus the pool token supply.
    /// @return Timestamp that balances were last cached.
    function getCache()
        public
        view
        virtual
        returns (
            uint16,
            uint104,
            uint104,
            uint32
        )
    {
        return (g1Fee, baseCached, fyTokenCached, blockTimestampLast);
    }

    /// Returns the all storage vars except for cumulativeRatioLast
    /// @dev This returns the same info as external getCache but uses a struct to help with stack too deep.
    /// @return cache A struct containing:
    /// g1Fee a fp4 number where 10_000 is 1.
    /// Cached base token balance.
    /// Cached virtual FY token balance which is the actual balance plus the pool token supply.
    /// Timestamp that balances were last cached.

    function _getCache() internal view virtual returns (Cache memory cache) {
        cache = Cache(g1Fee, baseCached, fyTokenCached, blockTimestampLast);
    }

    /// The "virtual" fyToken balance, which is the actual balance plus the pool token supply.
    /// @dev For more explanation about using the LP tokens as part of the virtual reserves see:
    /// https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
    /// @return The current balance of the pool's fyTokens plus the current balance of the pool's
    /// total supply of LP tokens as a uint104
    function getFYTokenBalance() public view virtual override returns (uint104) {
        return _getFYTokenBalance();
    }

    /// Returns the "virtual" fyToken balance, which is the real balance plus the pool token supply.
    function _getFYTokenBalance() internal view returns (uint104) {
        return (fyToken.balanceOf(address(this)) + _totalSupply).u104();
    }

    /// Retrieve any base tokens not accounted for in the cache
    /// @param to Address of the recipient of the base tokens.
    /// @return retrieved The amount of base tokens sent.
    function retrieveBase(address to) external virtual override returns (uint128 retrieved) {
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getBaseBalance() - baseCached; // Cache can never be above balances
        base.safeTransfer(to, retrieved);
        // Now the current balances match the cache, so no need to update the TWAR
    }

    /// Retrieve any fyTokens not accounted for in the cache
    /// @param to Address of the recipient of the fyTokens.
    /// @return retrieved The amount of fyTokens sent.
    function retrieveFYToken(address to) external virtual override returns (uint128 retrieved) {
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getFYTokenBalance() - fyTokenCached; // Cache can never be above balances
        fyToken.safeTransfer(to, retrieved);
        // Now the balances match the cache, so no need to update the TWAR
    }

    /// Sets g1 numerator and denominator
    /// @dev These numbers are converted to 64.64 and used to calculate g1 by dividing them, or g2 from 1/g1
    function setFees(uint16 g1Fee_) public auth {
        if (g1Fee_ > 10000) {
            revert InvalidFee(g1Fee_);
        }
        g1Fee = g1Fee_;
        emit FeesSet(g1Fee_);
    }
}
