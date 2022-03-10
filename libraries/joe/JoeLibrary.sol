// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

import "../../interfaces/IJoePair.sol";
import "../../interfaces/IJoeFactory.sol";
import "../../interfaces/IJoeERC20.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library JoeLibrary {
    using SafeMath for uint256;

    address private constant wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant wavaxUsdt =
        0xeD8CBD9F0cE3C6986b22002F03c6475CEb7a6256;
    address private constant wavaxUsdc =
        0x87Dee1cC9FFd464B79e058ba20387c1984aed86a;
    address private constant wavaxDai =
        0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1;
    IJoeFactory private constant joeFactory =
        IJoeFactory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);

    function getPriceInUsd(address tokenAddress)
        internal
        view
        returns (uint256)
    {
        return (getAvaxPrice().mul(getPriceInAvax(tokenAddress))) / 1e18; // 18
    }

    /// @notice Returns price of avax in usd.
    function getAvaxPrice() internal view returns (uint256) {
        uint256 priceFromWavaxUsdt = _getAvaxPrice(IJoePair(wavaxUsdt)); // 18
        uint256 priceFromWavaxUsdc = _getAvaxPrice(IJoePair(wavaxUsdc)); // 18
        uint256 priceFromWavaxDai = _getAvaxPrice(IJoePair(wavaxDai)); // 18

        uint256 sumPrice = priceFromWavaxUsdt.add(priceFromWavaxUsdc).add(
            priceFromWavaxDai
        ); // 18
        uint256 avaxPrice = sumPrice / 3; // 18
        return avaxPrice; // 18
    }

    /// @notice Returns value of wavax in units of stablecoins per wavax.
    /// @param pair A wavax-stablecoin pair.
    function _getAvaxPrice(IJoePair pair) internal view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        if (pair.token0() == wavax) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(pair.token1())); // 18
            return (reserve1.mul(1e18)) / reserve0; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(pair.token0())); // 18
            return (reserve0.mul(1e18)) / reserve1; // 18
        }
    }

    /// @notice Get the price of a token in Avax.
    /// @param tokenAddress Address of the token.
    /// @dev Need to be aware of decimals here, not always 18, it depends on the token.
    function getPriceInAvax(address tokenAddress)
        internal
        view
        returns (uint256)
    {
        if (tokenAddress == wavax) {
            return 1e18;
        }

        IJoePair pair = IJoePair(joeFactory.getPair(tokenAddress, wavax));

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        address token0Address = pair.token0();
        address token1Address = pair.token1();

        if (token0Address == wavax) {
            reserve1 = reserve1.mul(_tokenDecimalsMultiplier(token1Address)); // 18
            return (reserve0.mul(1e18)) / reserve1; // 18
        } else {
            reserve0 = reserve0.mul(_tokenDecimalsMultiplier(token0Address)); // 18
            return (reserve1.mul(1e18)) / reserve0; // 18
        }
    }

    /// @notice Calculates the multiplier needed to scale a token's numerical field to 18 decimals.
    /// @param tokenAddress Address of the token.
    function _tokenDecimalsMultiplier(address tokenAddress)
        internal
        pure
        returns (uint256)
    {
        uint256 decimalsNeeded = 18 - IJoeERC20(tokenAddress).decimals();
        return 1 * (10**decimalsNeeded);
    }
}
