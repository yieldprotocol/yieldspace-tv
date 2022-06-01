// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

interface IERC4626 is IERC20, IERC20Metadata {
    function mint(address receiver, uint256 shares) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function asset() external returns (IERC20);
}
