// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

// constants
uint256 constant WAD = 1e18;
uint256 constant MAX = type(uint256).max;
uint256 constant THREE_MONTHS = uint256(3) * 30 * 24 * 60 * 60;

uint256 constant INITIAL_SHARES = 1_100_000;
uint256 constant INITIAL_YVDAI = 1_100_000 * 1e18;
uint256 constant INITIAL_EUSDC = 1_100_000 * 1e18;

// 64.64
int128 constant ONE = 0x10000000000000000;

bytes32 constant TYPE_4626 = keccak256(abi.encodePacked("4626"));
bytes32 constant TYPE_NONTV = keccak256(abi.encodePacked("NonTv"));
bytes32 constant TYPE_YV = keccak256(abi.encodePacked("YearnVault"));
bytes32 constant TYPE_EULER = keccak256(abi.encodePacked("EulerVault"));

address constant MAINNET_DAI_DECEMBER_2022_POOL = 0x52956Fb3DC3361fd24713981917f2B6ef493DCcC;
address constant MAINNET_USDC_DECEMBER_2022_POOL = 0xB2fff7FEA1D455F0BCdd38DA7DeE98af0872a13a;
address constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
