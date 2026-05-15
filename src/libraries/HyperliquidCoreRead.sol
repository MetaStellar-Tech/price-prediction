// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

library HyperliquidCoreRead {
    error CoreReadFailed();
    error InvalidCoreReadPrice();
    error InvalidSizeDecimals();

    address internal constant PERP_ORACLE_PRICE_PRECOMPILE =
        0x0000000000000000000000000000000000000807;

    function readPerpOraclePriceE8(uint32 perpIndex, uint8 szDecimals)
        internal
        view
        returns (uint256)
    {
        if (szDecimals > 18) revert InvalidSizeDecimals();

        (bool success, bytes memory result) =
            PERP_ORACLE_PRICE_PRECOMPILE.staticcall(abi.encode(uint256(perpIndex)));
        if (!success || result.length == 0) revert CoreReadFailed();

        uint256 rawPrice = abi.decode(result, (uint256));
        if (rawPrice == 0) revert InvalidCoreReadPrice();

        if (szDecimals <= 6) {
            return (rawPrice * 1e8) / (10 ** (6 - szDecimals));
        }

        return rawPrice * 1e8 * (10 ** (szDecimals - 6));
    }
}
