// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";

interface IYVToken is IERC20, IERC20Metadata {
    function mint(address, uint256) external;
    // @notice Returns the price for a single Yearn Vault share.
    // @dev total vault assets / total token supply (calculated not cached)
    function getPricePerFullShare() external view returns (uint256);
}
