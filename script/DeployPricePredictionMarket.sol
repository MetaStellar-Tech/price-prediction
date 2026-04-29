// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {PricePredictionMarket} from "../src/PricePredictionMarket.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

contract DeployPricePredictionMarket {
    function deploy(
        IERC20 stakeToken,
        address admin,
        address operator,
        address feeRecipient,
        uint32 btcPerpIndex,
        uint8 btcSzDecimals
    ) external returns (PricePredictionMarket market) {
        market = new PricePredictionMarket(
            stakeToken, admin, operator, feeRecipient, btcPerpIndex, btcSzDecimals
        );
    }
}
