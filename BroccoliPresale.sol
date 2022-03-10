// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./FarmToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BroccoliPresale is
    ERC20("Broccoli Presale Token", "pBROC"),
    FarmToken
{}
