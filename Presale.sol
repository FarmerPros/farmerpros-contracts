// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./FarmToken.sol";
import "./FarmState.sol";
import "./PriceConverter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract Presale is FarmState, Ownable {
    FarmToken public farmToken;
    address public farmWallet;
    address public devWallet;
    address public safe;
    uint16 public dex;
    uint256 private farmTokenPriceInCents;
    uint16 private devPct = 10;
    uint16 private farmPct = 5;
    PriceConverter public priceConverter;

    using SafeMath for uint256;

    constructor(
        FarmToken _farmToken,
        address _farmWallet,
        address _devWallet,
        address _safe,
        uint16 _dex,
        uint256 _farmTokenPriceInCents,
        PriceConverter _priceConverter
    ) {
        farmToken = _farmToken;
        farmWallet = _farmWallet;
        devWallet = _devWallet;
        safe = _safe;
        farmTokenPriceInCents = _farmTokenPriceInCents;
        dex = _dex;
        priceConverter = _priceConverter;
    }

    function buy(uint256 amountOfTokens, address paymentToken) external {
        uint256 purchaseCost = priceConverter.convertToUsdPurchasePrice(
            dex,
            paymentToken,
            amountOfTokens,
            farmTokenPriceInCents
        );
        console.log("purchaseCost: %s", purchaseCost);
        console.log("amountOfTokens: %s", amountOfTokens);
        console.log("balance: %s", farmToken.balanceOf(address(this)));

        ERC20(paymentToken).transferFrom(msg.sender, safe, purchaseCost);
        farmToken.transfer(msg.sender, amountOfTokens);

        farmToken.mint(devWallet, amountOfTokens.mul(devPct).div(100));
        farmToken.mint(farmWallet, amountOfTokens.mul(farmPct).div(100));
    }

    function mint(address to, uint256 amount) external onlyOwner {
        farmToken.mint(to, amount);
        console.log("Minted %s", amount);
    }

    function burn(uint256 amount) external onlyOwner {
        console.log(
            "balance before burn: %s",
            farmToken.balanceOf(address(this))
        );
        farmToken.burn(address(this), amount);
        console.log("Burned %s", amount);
        console.log(
            "balance after burn: %s",
            farmToken.balanceOf(address(this))
        );
    }

    function releaseTo(address nextState) external override onlyOwner {
        farmToken.transferOwnership(nextState);
    }

    function setFarmToken(FarmToken _farmToken) external onlyOwner {
        farmToken = _farmToken;
    }

    function setFarmWallet(address _farmWallet) external onlyOwner {
        farmWallet = _farmWallet;
    }

    function setDevWallet(address _devWallet) external onlyOwner {
        devWallet = _devWallet;
    }

    function setSafe(address _safe) external onlyOwner {
        safe = _safe;
    }

    function setDex(uint16 _dex) external onlyOwner {
        dex = _dex;
    }

    function setDevPct(uint16 _devPct) external onlyOwner {
        devPct = _devPct;
    }

    function setFarmPct(uint16 _farmPct) external onlyOwner {
        farmPct = _farmPct;
    }

    function setPriceConverter(PriceConverter _priceConverter)
        external
        onlyOwner
    {
        priceConverter = _priceConverter;
    }

    function setFarmTokenPriceInCents(uint256 _farmTokenPriceInCents)
        external
        onlyOwner
    {
        farmTokenPriceInCents = _farmTokenPriceInCents;
    }
}
