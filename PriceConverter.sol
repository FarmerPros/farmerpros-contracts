// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libraries/joe/JoeLibrary.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract PriceConverter {
    address private constant USDT = 0xc7198437980c041c805A1EDcbA50c1Ce5db95118;

    enum Dex {
        JOE
    }

    using SafeMath for uint256;

    function getPriceInUsd(uint16 dex, address tokenAddress)
        public
        view
        returns (uint256 price)
    {
        if (dex == uint256(Dex.JOE)) {
            price = JoeLibrary.getPriceInUsd(tokenAddress);
        }
    }

    function convertToUsdPurchasePrice(
        uint16 dex,
        address paymentToken,
        uint256 amountOfTokens,
        uint256 tokenPriceInCents
    ) public view returns (uint256 purchasePrice) {
        console.log("Payment token: ", paymentToken);
        console.log("USDT: ", USDT);
        bool allowed = paymentToken == USDT;
        console.log("Allowed: ", allowed);
        require(allowed, "Payment has to be USDT");
        purchasePrice = amountOfTokens.div(10**12).mul(tokenPriceInCents).div(
            100
        );
    }

    function tokenPriceRatio(
        uint256 numerator,
        uint256 denominator,
        uint256 precision
    ) private pure returns (uint256 quotient) {
        // https://stackoverflow.com/questions/42738640/division-in-ethereum-solidity#42739843

        // caution, check safe-to-multiply here
        uint256 _numerator = numerator * 10**(precision + 1);
        // with rounding of last digit
        quotient = ((_numerator / denominator) + 5) / 10;
    }
}
