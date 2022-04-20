// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract FarmToken is ERC20, Ownable, ReentrancyGuard {
    event Mint(uint256 amount);
    event Burn(uint256 amount);

    FarmToken public presaleToken;
    uint256 public presaleExchangeDeadline;
    address public firstOwner;

    modifier beforeDeadline() {
        require(
            presaleExchangeDeadline == 0 ||
                block.timestamp < presaleExchangeDeadline,
            "Deadline to exchange presale token has passed."
        );
        _;
    }

    modifier onlyOwnerAndFirstOwner() {
        require(
            owner() == msg.sender || owner() == firstOwner,
            "You don't have the ownership."
        );
        _;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        emit Mint(amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
        emit Burn(amount);
    }

    /**
    Exchanges the presale token until the specified deadline
     */
    function exchangePresaleToken(uint256 exchangeAmount)
        external
        nonReentrant
        beforeDeadline
    {
        ERC20(presaleToken).transferFrom(
            msg.sender,
            address(this),
            exchangeAmount
        );
        _transfer(owner(), msg.sender, exchangeAmount);
    }

    function setPresaleToken(FarmToken token) external onlyOwner {
        presaleToken = token;
    }

    function setPresaleExchangeDeadline(uint256 deadline)
        external
        onlyOwnerAndFirstOwner
    {
        presaleExchangeDeadline = deadline;
    }

    function transferOwnershipTo(address newOwner) external onlyOwner {
        firstOwner = newOwner;
        transferOwnership(newOwner);
    }
}
