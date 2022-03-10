// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./FarmToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Broccoli is ERC20("Broccoli", "BROC"), FarmToken {}
