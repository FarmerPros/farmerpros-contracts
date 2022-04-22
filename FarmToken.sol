// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract FarmToken is ERC20, Ownable, ReentrancyGuard {
    event Mint(uint256 amount);

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
            msg.sender == owner() || msg.sender == firstOwner,
            "You don't have the ownership."
        );
        _;
    }

    /**
     * @dev Mints the token and transfers ownership.
     *
     * @param to address that recieves the mint and becomes the owner of this token
     * @param amount the amount to mint
     */
    function mintWithOwnershipTransfer(address to, uint256 amount)
        external
        onlyOwner
    {
        mint(to, amount);
        if (firstOwner == address(0)) {
            // saves the reference to the very first owner
            // before transferring ownership to the new owner
            firstOwner = owner();
        }
        transferOwnership(to);
    }

    // mint to first buyer
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        emit Mint(amount);
    }

    /**
     * @dev Transfers this token to the sender for the exchangeFrom() token at the specified amount.
     * (ie. the sender holding the token provided by exchangeFrom() will get this token transferred)
     */
    function exchangeToken(uint256 exchangeAmount)
        external
        nonReentrant
        beforeDeadline
    {
        require(
            address(exchangeFrom()) != address(0),
            "the token is not exchangeable."
        );
        ERC20(exchangeFrom()).transferFrom(
            msg.sender,
            address(this),
            exchangeAmount
        );
        _transfer(owner(), msg.sender, exchangeAmount);
    }

    function exchangeFrom() public view virtual returns (FarmToken) {
        return FarmToken(address(0));
    }

    function setPresaleExchangeDeadline(uint256 deadline)
        external
        onlyOwnerAndFirstOwner
    {
        presaleExchangeDeadline = deadline;
    }
}
