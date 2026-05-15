// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {PricePredictionMarket} from "../src/PricePredictionMarket.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

interface Vm {
    function addr(uint256 privateKey) external returns (address keyAddr);
    function envAddress(string calldata name) external view returns (address value);
    function envUint(string calldata name) external view returns (uint256 value);
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
}

contract DeployPricePredictionMarket {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error InvalidDeployerKey();
    error DeployerAddressMismatch(address expected, address actual);
    error InvalidEnvParameter();

    event PricePredictionMarketDeployed(
        address indexed market,
        address indexed stakeToken,
        address indexed admin,
        address operator,
        address feeRecipient,
        uint32 btcPerpIndex,
        uint8 btcSzDecimals
    );

    function run() external returns (PricePredictionMarket market) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        if (deployerPrivateKey == 0) revert InvalidDeployerKey();

        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        address derivedAddress = vm.addr(deployerPrivateKey);
        if (derivedAddress != deployerAddress) {
            revert DeployerAddressMismatch(deployerAddress, derivedAddress);
        }

        IERC20 stakeToken = IERC20(vm.envAddress("STAKE_TOKEN"));
        address admin = vm.envAddress("ADMIN");
        address operator = vm.envAddress("OPERATOR");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 btcPerpIndexRaw = vm.envUint("BTC_PERP_INDEX");
        uint256 btcSzDecimalsRaw = vm.envUint("BTC_SZ_DECIMALS");
        if (btcPerpIndexRaw > type(uint32).max || btcSzDecimalsRaw > 18) {
            revert InvalidEnvParameter();
        }
        uint32 btcPerpIndex = uint32(btcPerpIndexRaw);
        uint8 btcSzDecimals = uint8(btcSzDecimalsRaw);

        vm.startBroadcast(deployerPrivateKey);
        market = _deploy(stakeToken, admin, operator, feeRecipient, btcPerpIndex, btcSzDecimals);
        vm.stopBroadcast();
    }

    function deploy(
        IERC20 stakeToken,
        address admin,
        address operator,
        address feeRecipient,
        uint32 btcPerpIndex,
        uint8 btcSzDecimals
    ) external returns (PricePredictionMarket market) {
        market = _deploy(stakeToken, admin, operator, feeRecipient, btcPerpIndex, btcSzDecimals);
    }

    function _deploy(
        IERC20 stakeToken,
        address admin,
        address operator,
        address feeRecipient,
        uint32 btcPerpIndex,
        uint8 btcSzDecimals
    ) private returns (PricePredictionMarket market) {
        market = new PricePredictionMarket(
            stakeToken, admin, operator, feeRecipient, btcPerpIndex, btcSzDecimals
        );
        emit PricePredictionMarketDeployed(
            address(market),
            address(stakeToken),
            admin,
            operator,
            feeRecipient,
            btcPerpIndex,
            btcSzDecimals
        );
    }
}
