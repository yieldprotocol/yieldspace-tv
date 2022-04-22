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
/// @author Adapted by @devtooligan from original work by @alcueca and UniswapV2. Maths and whitepaper by @aniemburg.
contract Pool is PoolEvents, IYVPool, ERC20Permit, AccessControl {

    /* LIBRARIES
     *****************************************************************************************************************/

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
    /// as an "IERC20Like" and only cast as an IERC4626 when that functionality is needed in _getBaseCurrentPrice()
    /// We mostly use the core ERC20 (except when checking current price), so we cast the base token as an IERC20Like
    /// This wei, non-4626 compliant tokenized vault modules can import this contract and override that function.
    IERC20Like public immutable base;
    IFYToken public immutable fyToken;

    int128 public immutable mu; //                     The normalization coefficient, the initial c value, in 64.64
    int128 public immutable ts; //                     1 / seconds in 10 years (64.64)
    uint32 public immutable maturity; //                Maturity of the pool
    uint96 public immutable scaleFactor; //            Used to scale up to 18 decimals (not 64.64)

    /* STORAGE
     *****************************************************************************************************************/

    // The following 4 vars use one storage slot and can be retrieved with getCache()
    uint16 public g1Fee; //                             Fee this is a fp4 with a max of 10,000 representing 1
    uint104 internal baseCached; //                     Base token reserves, cached
    uint104 internal fyTokenCached; //                  fyToken reserves, cached
    uint32 internal blockTimestampLast; //              block.timestamp of last time reserve caches were updated

    /// ╔═╗┬ ┬┌┬┐┬ ┬┬  ┌─┐┌┬┐┬┬  ┬┌─┐  ╦═╗┌─┐┌┬┐┬┌─┐  ╦  ┌─┐┌─┐┌┬┐
    /// ║  │ │││││ ││  ├─┤ │ │└┐┌┘├┤   ╠╦╝├─┤ │ ││ │  ║  ├─┤└─┐ │
    /// ╚═╝└─┘┴ ┴└─┘┴─┘┴ ┴ ┴ ┴ └┘ └─┘  ╩╚═┴ ┴ ┴ ┴└─┘  ╩═╝┴ ┴└─┘ ┴
    /// a LAGGING, time weighted sum of the fyToken:base reserves ratio measured in ratio seconds.
    ///
    /// @dev Footgun alert!  Be careful, this number is probably not what you need and should normally be considered
    /// along with blockTimestampLast. Use currentCumulativeRatio() for consumption as a TWAR observation.
    /// In future pools, this function's visibility will be changed to internal.
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
        if ((maturity = uint32(IFYToken(fyToken_).maturity())) > type(uint32).max) revert MaturityOverflow();

        // set immutables
        fyToken = IFYToken(fyToken_);
        base = IERC20Like(base_);
        ts = ts_;
        scaleFactor = uint96(10**(18 - uint96(decimals))); // No more than 18 decimals allowed, reverts on underflow.
        mu = _getC();

        //set fee
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
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘
                                                                                       /            \
                                                                                              ^
    */
    /// Mint liquidity tokens in exchange for adding base and fyToken
    /// The amount of liquidity tokens to mint is calculated from the amount of unaccounted for fyToken in this contract.
    /// A proportional amount of base tokens need to be present in this contract, also unaccounted for.
    /// @dev _totalSupply > 0 check important here to prevent unauthorized initialization.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of liquidity tokens minted.
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
        return _mink(to, remainder, 0, minRatio, maxRatio);
    }

    /// This is the internal function for the external mint.  _mint is a common fn name in ERC20 implementations so we use menk here.
    /// ╦┌┐┌┬┌┬┐┬┌─┐┬  ┬┌─┐┌─┐  ╔═╗┌─┐┌─┐┬
    /// ║││││ │ │├─┤│  │┌─┘├┤   ╠═╝│ ││ ││
    /// ╩┘└┘┴ ┴ ┴┴ ┴┴─┘┴└─┘└─┘  ╩  └─┘└─┘┴─┘
    /// @dev This is the exact same as mint() but with auth added and supply > 0 check skipped.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of liquidity tokens minted.
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
            uint256,
            uint256,
            uint256
        )
    {
        if (_totalSupply != 0) revert Initialized();
        return _mink(to, remainder, 0, minRatio, maxRatio);
    }

    /*This is the internal function for the external mint.  _mint is a common fn name in ERC20 implementations so we use menk here.
    /// mintWithBase
                                                                                             V
                                  ┌───────────────────────────────┐                   \            /
                                  │                               │                 `    _......._     '   gm!
                                 \│                               │/                  .-:::::::::::-.
                                 \│                               │/             `   :    __    ____ :   /
                                  │         mintWithBase          │                 ::   / /   / __ \::
         B A S E     ──────►      │                               │  ──────▶    _   ::  / /   / /_/ /::   _
                                  │                               │                 :: / /___/ ____/ ::
                                 /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
                                  │                      \(^o^)/  │                   `-:::::::::::-'
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘                    /           \
                                                                                            ^
    */
    /// Mint liquidity tokens in exchange for adding only base
    /// The amount of liquidity tokens is calculated from the amount of fyToken to buy from the pool.
    /// The base tokens need to be present in this contract, unaccounted for.
    /// @dev _totalSupply > 0 check important here to prevent unauthorized initialization.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return The amount of liquidity tokens minted.
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
        return _mink(to, remainder, fyTokenToBuy, minRatio, maxRatio);
    }

    /// This is the internal function for the external mint.
    /// Because _mint is a common fn name in ERC20 implementations, the name of this fn is _mink.
    /// Mint liquidity tokens, with an optional internal trade to buy fyToken beforehand.
    /// The amount of liquidity tokens is calculated from the amount of fyTokenToBuy from the pool,
    /// plus the amount of extra, unaccounted for fyToken in this contract.
    /// The base tokens also need to be present in this contract, unaccounted for.
    /// @dev Warning: This fn expects that the pool has already been initialized or else it is being called by the initialize fn.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    function _mink(
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
        // Gather data
        uint256 supply = _totalSupply;
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint256 realFYTokenCached_ = fyTokenCached_ - supply; // The fyToken cache includes the virtual fyToken, equal to the supply

        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                ((uint256(baseCached_) * 1e18) / realFYTokenCached_ < minRatio) ||
                ((uint256(baseCached_) * 1e18) / realFYTokenCached_ > maxRatio)
            ) revert SlippageDuringMint((uint256(baseCached_) * 1e18) / realFYTokenCached_, minRatio, maxRatio);
        }

        // Calculate token amounts
        if (supply == 0) {
            // **First mint**
            // Initialize at 1 pool token minted per base token supplied
            baseIn = base.balanceOf(address(this)) - baseCached_;
            tokensMinted = baseIn;
        } else if (realFYTokenCached_ == 0) {
            // Edge case, no fyToken in the Pool after initialization
            baseIn = base.balanceOf(address(this)) - baseCached_;
            tokensMinted = (supply * baseIn) / baseCached_;
        } else {
            // There is an optional virtual trade before the mint
            uint256 baseToSell;
            if (fyTokenToBuy != 0) {
                baseToSell = _buyFYTokenPreview(fyTokenToBuy.u128(), baseCached_, fyTokenCached_, _computeG1(g1Fee_));
            }

            // We use all the available fyTokens, plus optional virtual trade. Surplus is in base tokens.
            fyTokenIn = fyToken.balanceOf(address(this)) - realFYTokenCached_;
            tokensMinted = (supply * (fyTokenToBuy + fyTokenIn)) / (realFYTokenCached_ - fyTokenToBuy);
            baseIn = baseToSell + ((baseCached_ + baseToSell) * tokensMinted) / supply;
            if ((base.balanceOf(address(this)) - baseCached_) < baseIn) {
                revert NotEnoughBaseIn((base.balanceOf(address(this)) - baseCached_), baseIn);
            }
        }

        // Update TWAR
        _update(
            (baseCached_ + baseIn).u128(),
            (fyTokenCached_ + fyTokenIn + tokensMinted).u128(), // Include "virtual" fyToken from new minted LP tokens
            baseCached_,
            fyTokenCached_
        );

        // Execute mint
        _mint(to, tokensMinted);

        // Return any unused base
        if ((base.balanceOf(address(this)) - baseCached_) - baseIn != 0)
            base.safeTransfer(remainder, (base.balanceOf(address(this)) - baseCached_) - baseIn);

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
                :: / /___/ ____/ ::     └~~~~~~►  B A S E
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
        return _burnInternal(baseTo, fyTokenTo, false, minRatio, maxRatio);
    }

    /* burnForBase

                        (   (
                        )    (
                    (  (|   (|  )
                 )   )\/ ( \/(( (    gg
                 ((  /     ))\))))\
                  )\(          |  )
                /:  | __    ____/:
                ::   / /   / __ \::   ~~~~~~~►   B A S E
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
    /// @return tokensBurned The amount of lp tokens burned.
    /// @return baseOut The amount of base tokens returned.
    function burnForBase(
        address to,
        uint256 minRatio,
        uint256 maxRatio
    ) external virtual override returns (uint256 tokensBurned, uint256 baseOut) {
        (tokensBurned, baseOut, ) = _burnInternal(to, address(0), true, minRatio, maxRatio);
    }

    /// Burn liquidity tokens in exchange for base.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param baseTo Wallet receiving the base.
    /// @param fyTokenTo Wallet receiving the fyToken.
    /// @param tradeToBase Whether the resulting fyToken should be traded for base tokens.
    /// @param minRatio Minimum ratio of base to fyToken in the pool.
    /// @param maxRatio Maximum ratio of base to fyToken in the pool.
    /// @return tokensBurned The amount of pool tokens burned.
    /// @return tokenOut The amount of base tokens returned.
    /// @return fyTokenOut The amount of fyTokens returned.
    function _burnInternal(
        address baseTo,
        address fyTokenTo,
        bool tradeToBase,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        returns (
            uint256 tokensBurned,
            uint256 tokenOut,
            uint256 fyTokenOut
        )
    {
        // Gather data
        tokensBurned = _balanceOf[address(this)];
        uint256 supply = _totalSupply;
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();

        uint256 realFYTokenCached_ = fyTokenCached_ - supply; // The fyToken cache includes the virtual fyToken, equal to the supply

        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                ((uint256(baseCached_) * 1e18) / realFYTokenCached_ < minRatio) ||
                ((uint256(baseCached_) * 1e18) / realFYTokenCached_ > maxRatio)
            ) {
                revert SlippageDuringBurn((uint256(baseCached_) * 1e18) / realFYTokenCached_, minRatio, maxRatio);
            }
        }

        // Calculate trade
        tokenOut = (tokensBurned * baseCached_) / supply;
        fyTokenOut = (tokensBurned * realFYTokenCached_) / supply;

        if (tradeToBase) {
            tokenOut +=
                YieldMath.sharesOutForFYTokenIn( //                         This is a virtual sell
                    (baseCached_ - tokenOut.u128()) * scaleFactor, //      Cache, minus virtual burn
                    (fyTokenCached_ - fyTokenOut.u128()) * scaleFactor, // Cache, minus virtual burn
                    fyTokenOut.u128() * scaleFactor, //                    Sell the virtual fyToken obtained
                    maturity - uint32(block.timestamp), //                  This can't be called after maturity
                    ts,
                    _computeG2(g1Fee_),
                    _getC(),
                    mu
                ) /
                scaleFactor;
            fyTokenOut = 0;
        }

        // Update TWAR
        _update(
            (baseCached_ - tokenOut).u128(),
            (fyTokenCached_ - fyTokenOut - tokensBurned).u128(),
            baseCached_,
            fyTokenCached_
        );

        // Transfer assets
        _burn(address(this), tokensBurned);
        base.safeTransfer(baseTo, tokenOut);
        if (fyTokenOut != 0) fyToken.safeTransfer(fyTokenTo, fyTokenOut);

        emit Liquidity(
            maturity,
            msg.sender,
            baseTo,
            fyTokenTo,
            tokenOut.i256(),
            fyTokenOut.i256(),
            -(tokensBurned.i256())
        );
    }

    /* TRADING FUNCTIONS
     ****************************************************************************************************************/

    /* buyBase

                         I want to buy `uint128 tokenOut` worth of base tokens.
             _______     I've already approved fyTokens to the pool so take what you need for the swap.
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|::      ok guy      │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :        ????       :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__GG__|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │  `tokenOut`  │\.-" ;  \        \________/        /+
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
    /// Buy base for fyToken
    /// The trader needs to have called `fyToken.approve`
    /// @param to Wallet receiving the base being bought
    /// @param tokenOut Amount of base being bought that will be deposited in `to` wallet
    /// @param max Maximum amount of fyToken that will be paid for the trade
    /// @return Amount of fyToken that will be taken from caller
    function buyBase(
        address to,
        uint128 tokenOut,
        uint128 max
    ) external virtual override returns (uint128) {
        // Calculate trade
        uint128 fyTokenBalance = _getFYTokenBalance();
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint128 fyTokenIn = _buyBasePreview(tokenOut, baseCached_, fyTokenCached_, _computeG2(g1Fee_));

        if (fyTokenBalance - fyTokenCached_ < fyTokenIn) {
            revert NotEnoughFYTokenIn(fyTokenBalance - fyTokenCached_, fyTokenIn);
        }

        if (fyTokenIn > max) revert SlippageDuringBuyBase(fyTokenIn, max);

        // Update TWAR
        _update(baseCached_ - tokenOut, fyTokenCached_ + fyTokenIn, baseCached_, fyTokenCached_);

        // Transfer assets
        base.safeTransfer(to, tokenOut);

        emit Trade(maturity, msg.sender, to, tokenOut.i128(), -(fyTokenIn.i128()));
        return fyTokenIn;
    }

    /// Returns how much fyToken would be required to buy `tokenOut` base.
    /// @param tokenOut Amount of base hypothetically desired.
    /// @return Amount of fyToken hypothetically required.
    function buyBasePreview(uint128 tokenOut) external view virtual override returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _buyBasePreview(tokenOut, baseCached_, fyTokenCached_, _computeG2(g1Fee_));
    }

    /// Returns how much fyToken would be required to buy `tokenOut` base.
    function _buyBasePreview(
        uint128 tokenOut,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) internal view beforeMaturity returns (uint128) {
        return
            YieldMath.fyTokenInForSharesOut(
                baseBalance * scaleFactor,
                fyTokenBalance * scaleFactor,
                tokenOut * scaleFactor,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) / scaleFactor;
    }

    /*buyFYToken

                         I want to buy `uint128 fyTokenOut` worth of fyTokens.
             _______     I've approved base for you to take what you need for the swap.
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│   hmm, let's see here     │     │    =======+
        \  \   \ == /      │ │   B A S E    │                      _____│_____│______    |+
         \  \___|  |___    │$│    ????      │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$            $│                 ( .'"                   '-.)+
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
              |  |  |           :    `fyTokenOut`   :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
 */
    /// Buy fyToken for base
    /// The trader needs to have called `base.approve`
    /// @param to Wallet receiving the fyToken being bought.
    /// @param fyTokenOut Amount of fyToken being bought that will be deposited in `to` wallet
    /// @param max Maximum amount of base token that will be paid for the trade
    /// @return Amount of base that will be taken from caller's wallet.
    function buyFYToken(
        address to,
        uint128 fyTokenOut,
        uint128 max
    ) external virtual override returns (uint128) {
        // Calculate trade
        uint128 baseBalance = _getBaseBalance();
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint128 baseIn = _buyFYTokenPreview(fyTokenOut, baseCached_, fyTokenCached_, _computeG1(g1Fee_));
        if (baseBalance - baseCached_ < baseIn) revert NotEnoughBaseIn((baseBalance - baseCached_), baseIn);
        if (baseIn > max) revert SlippageDuringBuyFYToken(baseIn, max);

        // Update TWAR
        _update(baseCached_ + baseIn, fyTokenCached_ - fyTokenOut, baseCached_, fyTokenCached_);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
        return baseIn;
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @return Amount of base hypothetically required.
    function buyFYTokenPreview(uint128 fyTokenOut) external view virtual override returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _buyFYTokenPreview(fyTokenOut, baseCached_, fyTokenCached_, _computeG1(g1Fee_));
    }

    /// Returns how much base would be required to buy `fyTokenOut` fyToken.
    function _buyFYTokenPreview(
        uint128 fyTokenOut,
        uint128 baseBalance,
        uint128 fyTokenBalance,
        int128 g1_
    ) internal view beforeMaturity returns (uint128) {
        uint128 baseIn = YieldMath.sharesInForFYTokenOut(
            baseBalance * scaleFactor,
            fyTokenBalance * scaleFactor,
            fyTokenOut * scaleFactor,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            g1_,
            _getC(),
            mu
        ) / scaleFactor;

        if ((fyTokenBalance - fyTokenOut) < (baseBalance + baseIn)) {
            revert InsufficientFYTokenBalance(fyTokenBalance - fyTokenOut, baseBalance + baseIn);
        }

        return baseIn;
    }

    /* sellBase

                         I've transfered you `uint128 baseIn` worth of base.
             _______     Can you swap them for fyTokens?
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│             can           │     │    =======+
        \  \   \ == /      │ │              │                      _____│_____│______    |+
         \  \___|  |___    │$│   `baseIn`   │                  .-'"___________________`-.|+
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
    /// The trader needs to have transferred the amount of base to sell to the pool before calling this fn.
    /// @param to Wallet receiving the fyToken being bought.
    /// @param min Minimum accepted amount of fyToken.
    /// @return Amount of fyToken that will be deposited on `to` wallet
    function sellBase(address to, uint128 min) external virtual override returns (uint128) {
        // Calculate trade
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint104 baseBalance = _getBaseBalance();
        uint104 fyTokenBalance = _getFYTokenBalance();
        uint128 baseIn = baseBalance - baseCached_;
        uint128 fyTokenOut = _sellBasePreview(baseIn, baseCached_, fyTokenBalance, _computeG1(g1Fee_));

        // Slippage check
        if (fyTokenOut < min) revert SlippageDuringSellBase(fyTokenOut, min);

        // Update TWAR
        _update(baseBalance, fyTokenBalance - fyTokenOut, baseCached_, fyTokenCached_);

        // Transfer assets
        fyToken.safeTransfer(to, fyTokenOut);

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
        return fyTokenOut;
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    /// @param baseIn Amount of base hypothetically sold.
    /// @return Amount of fyToken hypothetically bought.
    function sellBasePreview(uint128 baseIn) external view virtual override returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _sellBasePreview(baseIn, baseCached_, fyTokenCached_, _computeG1(g1Fee_));
    }

    /// Returns how much fyToken would be obtained by selling `baseIn` base
    function _sellBasePreview(
        uint128 baseIn,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g1_
    ) internal view beforeMaturity returns (uint128) {
        uint128 fyTokenOut = YieldMath.fyTokenOutForSharesIn(
            baseBalance * scaleFactor,
            fyTokenBalance * scaleFactor,
            baseIn * scaleFactor,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            g1_,
            _getC(),
            mu
        ) / scaleFactor;

        if (fyTokenBalance - fyTokenOut < baseBalance + baseIn) {
            revert InsufficientFYTokenBalance(fyTokenBalance - fyTokenOut, baseBalance + baseIn);
        }

        return fyTokenOut;
    }

    /*sellFYToken
                         I've transferred you `uint128 fyTokenIn` worth of fyTokens.
             _______     Can you swap them for base?
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|:::   I think so    │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :     `fyTokenIn`   :         ( .'"                   '-.)+
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
    /// @param to Wallet receiving the base being bought
    /// @param min Minimum accepted amount of base
    /// @return Amount of base that will be deposited on `to` wallet
    function sellFYToken(address to, uint128 min) external virtual override returns (uint128) {
        // Calculate trade
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        uint104 fyTokenBalance = _getFYTokenBalance();
        uint104 baseBalance = _getBaseBalance();
        uint128 fyTokenIn = fyTokenBalance - fyTokenCached_;
        uint128 baseOut = _sellFYTokenPreview(fyTokenIn, baseCached_, fyTokenCached_, _computeG2(g1Fee_));

        // Slippage check
        if (baseOut < min) revert SlippageDuringSellFYToken(baseOut, min);

        // Update TWAR
        _update(baseBalance - baseOut, fyTokenBalance, baseCached_, fyTokenCached_);

        // Transfer assets
        base.safeTransfer(to, baseOut);

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
        return baseOut;
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return Amount of base hypothetically bought.
    function sellFYTokenPreview(uint128 fyTokenIn) public view virtual returns (uint128) {
        (uint16 g1Fee_, uint104 baseCached_, uint104 fyTokenCached_, ) = getCache();
        return _sellFYTokenPreview(fyTokenIn, baseCached_, fyTokenCached_, _computeG2(g1Fee_));
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    function _sellFYTokenPreview(
        uint128 fyTokenIn,
        uint104 baseBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) internal view beforeMaturity returns (uint128) {
        return
            YieldMath.sharesOutForFYTokenIn(
                baseBalance * scaleFactor,
                fyTokenBalance * scaleFactor,
                fyTokenIn * scaleFactor,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) / scaleFactor;
    }

    /* BALANCES MANAGEMENT AND ADMINISTRATIVE FUNCTIONS
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

    /// Returns the base balance.
    /// @return The current balance of the pool's base tokens.
    function getBaseBalance() public view virtual override returns (uint104) {
        return _getBaseBalance();
    }

    /// Returns the base token current price.
    /// @return The price of 1 base token in terms of its underlying as fp18 cast as uint256.
    function getBaseCurrentPrice() external view returns (uint256) {
        return _getBaseCurrentPrice();
    }

    /// Returns the base token current price.
    /// @return The price of 1 base token in terms of its underlying as fp18 cast as uint256.
    function _getBaseCurrentPrice() internal view virtual returns (uint256) {

        return IERC4626(address(base)).convertToAssets(10**base.decimals());
    }

    /// The "virtual" fyToken balance, which is the actual balance plus the pool token supply.
    /// @dev For more explanation about using the LP tokens as part of the virtual reserves see:
    /// https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
    /// @return The current balance of the pool's fyTokens plus the current balance of the pool's
    /// total supply of LP tokens as a uint104
    function getFYTokenBalance() public view virtual override returns (uint104) {
        return _getFYTokenBalance();
    }

    /// Returns the all storage vars except for cumulativeRatioLast
    /// @return g1Fee  This is a fp4 number where 10000 is 1.
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
        currentCumulativeRatio_ = cumulativeRatioLast + ((uint256(fyTokenCached) * 1e27) * (timeElapsed)) / baseCached;
    }

    /// Retrieve any base tokens not accounted for in the cache
    /// @param to Address of the recipient of the base tokens.
    /// @return retrieved The amount of base tokens sent.
    function retrieveBase(address to) external virtual override returns (uint128 retrieved) {
        // TODO: any interest in adding auth to these?
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getBaseBalance() - baseCached; // Cache can never be above balances
        base.safeTransfer(to, retrieved);
        // Now the current balances match the cache, so no need to update the TWAR
    }

    /// Retrieve any fyTokens not accounted for in the cache
    /// @param to Address of the recipient of the fyTokens.
    /// @return retrieved The amount of fyTokens sent.
    function retrieveFYToken(address to) external virtual override returns (uint128 retrieved) {
        // TODO: any interest in adding auth to these?
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getFYTokenBalance() - fyTokenCached; // Cache can never be above balances
        fyToken.safeTransfer(to, retrieved);
        // Now the balances match the cache, so no need to update the TWAR
    }

    /// Updates the cache to match the actual balances.
    function sync() external virtual {
        _update(_getBaseBalance(), _getFYTokenBalance(), baseCached, fyTokenCached);
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

    /// Returns the ratio of net proceeds after fees, for buying fyToken
    function _computeG1(uint16 g1Fee_) internal pure returns (int128) {
        return uint256(g1Fee_).fromUInt().div(uint256(10000).fromUInt());
    }

    /// Returns the ratio of net proceeds after fees, for selling fyToken
    function _computeG2(uint16 g1Fee_) internal pure returns (int128) {
        // Divide 1 (64.64) by g1
        return int128(YieldMath.ONE).div(uint256(g1Fee_).fromUInt().div(uint256(10000).fromUInt()));
    }

    /// Returns the base balance
    function _getBaseBalance() internal view returns (uint104) {
        return base.balanceOf(address(this)).u104();
    }

    /// Returns the c based on the current price
    function _getC() internal view returns (int128) {

        return ((_getBaseCurrentPrice() * scaleFactor)).fromUInt().div(uint256(1e18).fromUInt());
    }

    /// Returns the "virtual" fyToken balance, which is the real balance plus the pool token supply.
    function _getFYTokenBalance() internal view returns (uint104) {
        return (fyToken.balanceOf(address(this)) + _totalSupply).u104();
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
        baseCached = baseBalance.u104();
        fyTokenCached = fyBalance.u104();

        emit Sync(baseCached, fyTokenCached, newCumulativeRatioLast);
    }
}
