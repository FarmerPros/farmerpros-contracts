// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract FarmToken is ERC20, Ownable {
    event Mint(uint256 amount);
    event Burn(uint256 amount);

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit Burn(amount);
    }

    function transferToken(address recipient, uint256 amount)
        external
        onlyOwner
        returns (bool)
    {
        return transfer(recipient, amount);
    }

    function transferTokenFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external onlyOwner returns (bool) {
        return transferFrom(sender, recipient, amount);
    }
}
