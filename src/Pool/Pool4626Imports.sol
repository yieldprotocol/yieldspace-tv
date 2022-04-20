// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./Pool4626Events.sol";
import "./Pool4626Errors.sol";

import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U104.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I256.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128U104.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/MinimalTransferHelper.sol";

import {Exp64x64} from "../Exp64x64.sol";
import {Math64x64} from "../Math64x64.sol";
import {YieldMath} from "../YieldMath.sol";
import {IYVPool} from "../interfaces/IYVPool.sol";
import {IERC4626} from  "../interfaces/IERC4626.sol";
import {IERC20Metadata as IERC20Like} from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
