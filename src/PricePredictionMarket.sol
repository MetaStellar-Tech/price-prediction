// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "./interfaces/IERC20.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";
import {HyperliquidCoreRead} from "./libraries/HyperliquidCoreRead.sol";

contract PricePredictionMarket {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;

    enum Direction {
        Up,
        Down
    }

    enum RoundState {
        None,
        Betting,
        BettingClosed,
        Settled,
        Cleaned
    }

    enum Outcome {
        None,
        Up,
        Down,
        Draw
    }

    struct PricingConfig {
        uint256 basePriceBps;
        uint256 maxTimePremiumBps;
        uint256 maxTrendAdjustmentBps;
        uint256 trendMoveCapBps;
        uint256 maxPoolImbalanceAdjustmentBps;
        uint256 minSharePriceBps;
        uint256 maxSharePriceBps;
    }

    struct Round {
        RoundState state;
        Outcome outcome;
        uint256 startTime;
        uint256 stopBetTime;
        uint256 settleTime;
        uint256 basePriceE8;
        uint256 finalPriceE8;
        uint256 upPool;
        uint256 downPool;
        uint256 upShares;
        uint256 downShares;
        uint256 feeAmount;
        uint256 cleanupIndex;
        bool feeTransferred;
    }

    struct Position {
        uint256 upStake;
        uint256 downStake;
        uint256 upShares;
        uint256 downShares;
    }

    IERC20 public immutable stakeToken;

    address public admin;
    address public operator;
    address public feeRecipient;

    uint32 public btcPerpIndex;
    uint8 public btcSzDecimals;
    uint256 public roundDuration = 60 seconds;
    uint256 public stopBetOffset = 50 seconds;
    uint256 public feeBps = 500;
    uint256 public currentRoundId;
    PricingConfig public pricingConfig;

    mapping(uint256 roundId => Round) public rounds;
    mapping(uint256 roundId => address[]) private _participants;
    mapping(uint256 roundId => mapping(address account => bool)) private _isParticipant;
    mapping(uint256 roundId => mapping(address account => Position)) public positions;

    error Unauthorized();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidState();
    error InvalidParameter();
    error BetWindowClosed();
    error StopBetTooEarly();
    error SettleTooEarly();
    error SlippageExceeded();
    error NoParticipantsToCleanup();

    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);
    event OperatorUpdated(address indexed oldOperator, address indexed newOperator);
    event FeeRecipientUpdated(address indexed oldFeeRecipient, address indexed newFeeRecipient);
    event CoreReadConfigUpdated(uint32 btcPerpIndex, uint8 btcSzDecimals);
    event TimingConfigUpdated(uint256 roundDuration, uint256 stopBetOffset);
    event FeeBpsUpdated(uint256 feeBps);
    event PricingConfigUpdated(PricingConfig config);
    event RoundStarted(uint256 indexed roundId, uint256 startTime, uint256 basePriceE8);
    event BetPlaced(
        uint256 indexed roundId,
        address indexed user,
        Direction indexed direction,
        uint256 amount,
        uint256 shares,
        uint256 averageSharePriceBps
    );
    event BettingStopped(uint256 indexed roundId, uint256 stopTime);
    event RoundSettled(
        uint256 indexed roundId, Outcome outcome, uint256 finalPriceE8, uint256 feeAmount
    );
    event CleanupPayout(
        uint256 indexed roundId, address indexed user, uint256 amount, bool isWinner
    );
    event CleanupCompleted(uint256 indexed roundId, uint256 feeAmount);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Unauthorized();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert Unauthorized();
        _;
    }

    constructor(
        IERC20 stakeToken_,
        address admin_,
        address operator_,
        address feeRecipient_,
        uint32 btcPerpIndex_,
        uint8 btcSzDecimals_
    ) {
        if (
            address(stakeToken_) == address(0) || admin_ == address(0) || operator_ == address(0)
                || feeRecipient_ == address(0)
        ) revert InvalidAddress();

        stakeToken = stakeToken_;
        admin = admin_;
        operator = operator_;
        feeRecipient = feeRecipient_;
        btcPerpIndex = btcPerpIndex_;
        btcSzDecimals = btcSzDecimals_;
        pricingConfig = PricingConfig({
            basePriceBps: 10_000,
            maxTimePremiumBps: 5_000,
            maxTrendAdjustmentBps: 4_000,
            trendMoveCapBps: 1_000,
            maxPoolImbalanceAdjustmentBps: 6_000,
            minSharePriceBps: 2_000,
            maxSharePriceBps: 30_000
        });
    }

    function participants(uint256 roundId) external view returns (address[] memory) {
        return _participants[roundId];
    }

    function participantCount(uint256 roundId) external view returns (uint256) {
        return _participants[roundId].length;
    }

    function latestBtcPriceE8() public view returns (uint256) {
        return HyperliquidCoreRead.readPerpOraclePriceE8(btcPerpIndex, btcSzDecimals);
    }

    function startRound() external onlyOperator returns (uint256 roundId) {
        if (currentRoundId != 0 && rounds[currentRoundId].state != RoundState.Cleaned) {
            revert InvalidState();
        }

        uint256 basePriceE8 = latestBtcPriceE8();
        roundId = currentRoundId + 1;
        currentRoundId = roundId;

        Round storage round = rounds[roundId];
        round.state = RoundState.Betting;
        round.startTime = block.timestamp;
        round.stopBetTime = block.timestamp + stopBetOffset;
        round.settleTime = block.timestamp + roundDuration;
        round.basePriceE8 = basePriceE8;

        emit RoundStarted(roundId, block.timestamp, basePriceE8);
    }

    function bet(Direction direction, uint256 amount, uint256 minSharesOut)
        external
        returns (uint256 shares)
    {
        if (amount == 0) revert InvalidAmount();

        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];
        if (round.state != RoundState.Betting) revert InvalidState();
        if (block.timestamp >= round.stopBetTime) revert BetWindowClosed();

        uint256 currentPriceE8 = latestBtcPriceE8();
        uint256 beforePrice = quoteSharePriceBps(roundId, direction, currentPriceE8, 0);
        uint256 afterPrice = quoteSharePriceBps(roundId, direction, currentPriceE8, amount);
        uint256 averagePrice = (beforePrice + afterPrice) / 2;

        shares = (amount * BPS) / averagePrice;
        if (shares < minSharesOut) revert SlippageExceeded();

        if (!_isParticipant[roundId][msg.sender]) {
            _isParticipant[roundId][msg.sender] = true;
            _participants[roundId].push(msg.sender);
        }

        Position storage position = positions[roundId][msg.sender];
        if (direction == Direction.Up) {
            round.upPool += amount;
            round.upShares += shares;
            position.upStake += amount;
            position.upShares += shares;
        } else {
            round.downPool += amount;
            round.downShares += shares;
            position.downStake += amount;
            position.downShares += shares;
        }

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit BetPlaced(roundId, msg.sender, direction, amount, shares, averagePrice);
    }

    function stopBet() external onlyOperator {
        Round storage round = rounds[currentRoundId];
        if (round.state != RoundState.Betting) revert InvalidState();
        if (block.timestamp < round.stopBetTime) revert StopBetTooEarly();

        round.state = RoundState.BettingClosed;
        emit BettingStopped(currentRoundId, block.timestamp);
    }

    function settle() external onlyOperator {
        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];
        if (round.state != RoundState.BettingClosed) revert InvalidState();
        if (block.timestamp < round.settleTime) revert SettleTooEarly();

        uint256 finalPriceE8 = latestBtcPriceE8();
        round.finalPriceE8 = finalPriceE8;

        if (finalPriceE8 > round.basePriceE8) {
            round.outcome = Outcome.Up;
            round.feeAmount = (round.downPool * feeBps) / BPS;
        } else if (finalPriceE8 < round.basePriceE8) {
            round.outcome = Outcome.Down;
            round.feeAmount = (round.upPool * feeBps) / BPS;
        } else {
            round.outcome = Outcome.Draw;
            round.feeAmount = 0;
        }

        round.state = RoundState.Settled;
        emit RoundSettled(roundId, round.outcome, finalPriceE8, round.feeAmount);
    }

    function cleanup(uint256 roundId, uint256 maxCount) external {
        if (maxCount == 0) revert InvalidAmount();

        Round storage round = rounds[roundId];
        if (round.state != RoundState.Settled) revert InvalidState();

        uint256 count = _participants[roundId].length;
        uint256 index = round.cleanupIndex;
        if (index >= count) {
            _completeCleanup(roundId, round);
            return;
        }

        uint256 end = index + maxCount;
        if (end > count) end = count;

        while (index < end) {
            address user = _participants[roundId][index];
            (uint256 payout, bool isWinner) = _payoutFor(roundId, user);
            if (payout != 0) {
                stakeToken.safeTransfer(user, payout);
            }
            emit CleanupPayout(roundId, user, payout, isWinner);
            unchecked {
                ++index;
            }
        }

        round.cleanupIndex = index;

        if (index == count) {
            _completeCleanup(roundId, round);
        }
    }

    function quoteCurrentSharePriceBps(Direction direction) external view returns (uint256) {
        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];
        if (round.state != RoundState.Betting) revert InvalidState();
        return quoteSharePriceBps(roundId, direction, latestBtcPriceE8(), 0);
    }

    function quoteSharePriceBps(
        uint256 roundId,
        Direction direction,
        uint256 currentPriceE8,
        uint256 addedAmount
    ) public view returns (uint256) {
        Round storage round = rounds[roundId];
        if (round.state == RoundState.None || round.basePriceE8 == 0) revert InvalidState();
        if (currentPriceE8 == 0) revert InvalidParameter();

        PricingConfig memory config = pricingConfig;
        int256 priceBps = int256(config.basePriceBps);
        priceBps += int256(_timePremiumBps(round, config));
        priceBps += _trendAdjustmentBps(round.basePriceE8, currentPriceE8, direction, config);
        priceBps += _poolImbalanceAdjustmentBps(round, direction, addedAmount, config);

        if (priceBps < int256(config.minSharePriceBps)) return config.minSharePriceBps;
        if (priceBps > int256(config.maxSharePriceBps)) return config.maxSharePriceBps;
        return uint256(priceBps);
    }

    function previewBet(Direction direction, uint256 amount)
        external
        view
        returns (
            uint256 beforePriceBps,
            uint256 afterPriceBps,
            uint256 averagePriceBps,
            uint256 shares
        )
    {
        if (amount == 0) revert InvalidAmount();
        uint256 roundId = currentRoundId;
        Round storage round = rounds[roundId];
        if (round.state != RoundState.Betting) revert InvalidState();

        uint256 currentPriceE8 = latestBtcPriceE8();
        beforePriceBps = quoteSharePriceBps(roundId, direction, currentPriceE8, 0);
        afterPriceBps = quoteSharePriceBps(roundId, direction, currentPriceE8, amount);
        averagePriceBps = (beforePriceBps + afterPriceBps) / 2;
        shares = (amount * BPS) / averagePriceBps;
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert InvalidAddress();
        emit AdminUpdated(admin, newAdmin);
        admin = newAdmin;
    }

    function setOperator(address newOperator) external onlyAdmin {
        if (newOperator == address(0)) revert InvalidAddress();
        emit OperatorUpdated(operator, newOperator);
        operator = newOperator;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyAdmin {
        if (newFeeRecipient == address(0)) revert InvalidAddress();
        emit FeeRecipientUpdated(feeRecipient, newFeeRecipient);
        feeRecipient = newFeeRecipient;
    }

    function setCoreReadConfig(uint32 newBtcPerpIndex, uint8 newBtcSzDecimals) external onlyAdmin {
        if (newBtcSzDecimals > 18) revert InvalidParameter();
        btcPerpIndex = newBtcPerpIndex;
        btcSzDecimals = newBtcSzDecimals;
        emit CoreReadConfigUpdated(newBtcPerpIndex, newBtcSzDecimals);
    }

    function setTimingConfig(uint256 newRoundDuration, uint256 newStopBetOffset)
        external
        onlyAdmin
    {
        if (newRoundDuration == 0 || newStopBetOffset >= newRoundDuration) {
            revert InvalidParameter();
        }
        roundDuration = newRoundDuration;
        stopBetOffset = newStopBetOffset;
        emit TimingConfigUpdated(newRoundDuration, newStopBetOffset);
    }

    function setFeeBps(uint256 newFeeBps) external onlyAdmin {
        if (newFeeBps > 2_000) revert InvalidParameter();
        feeBps = newFeeBps;
        emit FeeBpsUpdated(newFeeBps);
    }

    function setPricingConfig(PricingConfig calldata newConfig) external onlyAdmin {
        _validatePricingConfig(newConfig);
        pricingConfig = newConfig;
        emit PricingConfigUpdated(newConfig);
    }

    function _validatePricingConfig(PricingConfig memory config) private pure {
        if (
            config.basePriceBps == 0 || config.trendMoveCapBps == 0 || config.minSharePriceBps == 0
                || config.minSharePriceBps > config.maxSharePriceBps
        ) revert InvalidParameter();
        if (config.maxSharePriceBps > 100_000) revert InvalidParameter();
    }

    function _timePremiumBps(Round storage round, PricingConfig memory config)
        private
        view
        returns (uint256)
    {
        uint256 elapsed = block.timestamp > round.startTime ? block.timestamp - round.startTime : 0;
        if (elapsed > roundDuration) elapsed = roundDuration;
        return (config.maxTimePremiumBps * elapsed) / roundDuration;
    }

    function _trendAdjustmentBps(
        uint256 basePriceE8,
        uint256 currentPriceE8,
        Direction direction,
        PricingConfig memory config
    ) private pure returns (int256) {
        if (currentPriceE8 == basePriceE8) return 0;

        uint256 diff = currentPriceE8 > basePriceE8
            ? currentPriceE8 - basePriceE8
            : basePriceE8 - currentPriceE8;
        uint256 moveBps = (diff * BPS) / basePriceE8;
        if (moveBps > config.trendMoveCapBps) moveBps = config.trendMoveCapBps;
        uint256 magnitude = (config.maxTrendAdjustmentBps * moveBps) / config.trendMoveCapBps;

        bool upTrend = currentPriceE8 > basePriceE8;
        bool sameDirection =
            (upTrend && direction == Direction.Up) || (!upTrend && direction == Direction.Down);

        return sameDirection ? int256(magnitude) : -int256(magnitude);
    }

    function _poolImbalanceAdjustmentBps(
        Round storage round,
        Direction direction,
        uint256 addedAmount,
        PricingConfig memory config
    ) private view returns (int256) {
        uint256 upPool = round.upPool;
        uint256 downPool = round.downPool;
        if (direction == Direction.Up) {
            upPool += addedAmount;
        } else {
            downPool += addedAmount;
        }

        uint256 totalPool = upPool + downPool;
        if (totalPool == 0) return 0;

        uint256 sidePool = direction == Direction.Up ? upPool : downPool;
        uint256 sidePoolShareBps = (sidePool * BPS) / totalPool;
        int256 skewBps = int256(sidePoolShareBps) - int256(BPS / 2);
        return (int256(config.maxPoolImbalanceAdjustmentBps) * skewBps) / int256(BPS / 2);
    }

    function _payoutFor(uint256 roundId, address user)
        private
        view
        returns (uint256 payout, bool isWinner)
    {
        Round storage round = rounds[roundId];
        Position storage position = positions[roundId][user];

        if (round.outcome == Outcome.Draw) {
            payout = position.upStake + position.downStake;
            return (payout, payout != 0);
        }

        if (round.outcome == Outcome.Up) {
            if (position.upShares == 0) return (0, false);
            uint256 payoutPool = round.upPool + round.downPool - round.feeAmount;
            return ((payoutPool * position.upShares) / round.upShares, true);
        }

        if (round.outcome == Outcome.Down) {
            if (position.downShares == 0) return (0, false);
            uint256 payoutPool = round.upPool + round.downPool - round.feeAmount;
            return ((payoutPool * position.downShares) / round.downShares, true);
        }
    }

    function _completeCleanup(uint256 roundId, Round storage round) private {
        if (round.feeTransferred) revert NoParticipantsToCleanup();

        round.feeTransferred = true;
        uint256 feeAmount = round.feeAmount;
        if (feeAmount != 0) {
            stakeToken.safeTransfer(feeRecipient, feeAmount);
        }
        round.state = RoundState.Cleaned;
        emit CleanupCompleted(roundId, feeAmount);
    }
}
