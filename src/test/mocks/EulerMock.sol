// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;
import {IERC20Metadata} from "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";

/// @notice This contract mimics the Euler router
contract EulerMock {

    /// @notice Use Euler to move tokens
    function move(IERC20Metadata token, address from, address to, uint256 amount) external {
        token.transferFrom(from, to, amount);
    }
}
