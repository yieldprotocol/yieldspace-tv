// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;
import "lib/yield-utils-v2/src/token/IERC20Metadata.sol";
import "lib/yield-utils-v2/src/token/IERC20.sol";

interface IERC20Like is IERC20, IERC20Metadata {
    function mint(address receiver, uint256 shares) external;
}