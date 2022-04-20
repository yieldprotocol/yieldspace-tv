// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;

import {console} from "forge-std/console.sol";

function almostEqual(
    uint256 x,
    uint256 y,
    uint256 p
) view {
    uint256 diff = x > y ? x - y : y - x;
    if (diff / p != 0) {
        console.log(x);
        console.log("is not almost equal to");
        console.log(y);
        console.log("with p of:");
        console.log(p);
        revert();
    }
}
