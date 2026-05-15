// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {PricePredictionMarket} from "../src/PricePredictionMarket.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {Test} from "./utils/Test.sol";

contract PricePredictionMarketTest is Test {
    address private constant CORE_READ = 0x0000000000000000000000000000000000000807;
    uint32 private constant BTC_PERP_INDEX = 0;
    uint8 private constant BTC_SZ_DECIMALS = 5;

    address private admin = address(0xA11CE);
    address private operator = address(0xB0B);
    address private feeRecipient = address(0xFEE);
    address private alice = address(0xA1);
    address private bob = address(0xB2);
    address private carol = address(0xC3);
    address private arb = address(0xA4B);

    MockERC20 private token;
    PricePredictionMarket private market;

    function setUp() public {
        token = new MockERC20("Mock USDC", "USDC", 6);
        market = new PricePredictionMarket(
            token, admin, operator, feeRecipient, BTC_PERP_INDEX, BTC_SZ_DECIMALS
        );

        _mintAndApprove(alice, 10_000e6);
        _mintAndApprove(bob, 10_000e6);
        _mintAndApprove(carol, 10_000e6);
        _mintAndApprove(arb, 10_000e6);
    }

    function testOperatorStartsRoundFromCoreReadPrice() public {
        _mockPrice(100_000e8);

        vm.prank(operator);
        uint256 roundId = market.startRound();

        assertEq(roundId, 1);
        (
            PricePredictionMarket.RoundState state,
            ,
            uint256 startTime,
            uint256 stopBetTime,
            uint256 settleTime,
            uint256 basePriceE8,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
        ) = market.rounds(1);
        assertEq(uint256(state), uint256(PricePredictionMarket.RoundState.Betting));
        assertEq(stopBetTime, startTime + 120);
        assertEq(settleTime, startTime + 130);
        assertEq(basePriceE8, 100_000e8);
    }

    function testOnlyOperatorCanStartButAnyoneCanStopAndSettleAfterDeadlines() public {
        _mockPrice(100_000e8);

        vm.expectRevert(PricePredictionMarket.Unauthorized.selector);
        market.startRound();

        vm.prank(operator);
        market.startRound();

        vm.expectRevert(PricePredictionMarket.StopBetTooEarly.selector);
        market.stopBet();

        _warpToElapsed(1, 120);
        vm.prank(alice);
        market.stopBet();

        _warpToElapsed(1, 130);
        _mockPrice(100_100e8);
        vm.prank(alice);
        market.settle();

        (PricePredictionMarket.RoundState state, PricePredictionMarket.Outcome outcome,,,,,,,,,,,,)
        = market.rounds(1);
        assertEq(uint256(state), uint256(PricePredictionMarket.RoundState.Settled));
        assertEq(uint256(outcome), uint256(PricePredictionMarket.Outcome.NoContest));
    }

    function testAnyoneCanSettleFromBettingAfterDeadline() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        _bet(alice, PricePredictionMarket.Direction.Up, 10e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 10e6, 0);

        _warpToElapsed(1, 130);
        _mockPrice(100_100e8);
        vm.prank(carol);
        market.settle();

        (PricePredictionMarket.RoundState state, PricePredictionMarket.Outcome outcome,,,,,,,,,,,,)
        = market.rounds(1);
        assertEq(uint256(state), uint256(PricePredictionMarket.RoundState.Settled));
        assertEq(uint256(outcome), uint256(PricePredictionMarket.Outcome.Up));
    }

    function testAdminUpdatesParameters() public {
        vm.prank(admin);
        market.setOperator(carol);
        assertEq(market.operator(), carol);

        vm.prank(admin);
        market.setFeeRecipient(bob);
        assertEq(market.feeRecipient(), bob);

        vm.prank(admin);
        market.setTimingConfig(120, 90);
        assertEq(market.roundDuration(), 120);
        assertEq(market.stopBetOffset(), 90);

        vm.prank(admin);
        market.setFeeBps(700);
        assertEq(market.feeBps(), 700);

        PricePredictionMarket.PricingConfig memory config = PricePredictionMarket.PricingConfig({
            basePriceBps: 10_000,
            maxTimePremiumBps: 4_000,
            maxTrendAdjustmentBps: 3_000,
            trendMoveCapBps: 800,
            maxPoolImbalanceAdjustmentBps: 5_000,
            minSharePriceBps: 2_500,
            maxSharePriceBps: 25_000
        });
        vm.prank(admin);
        market.setPricingConfig(config);
        (uint256 basePriceBps,,,,,, uint256 maxSharePriceBps) = market.pricingConfig();
        assertEq(basePriceBps, 10_000);
        assertEq(maxSharePriceBps, 25_000);
    }

    function testBetUsesTrendTimePoolAndSlippagePricing() public {
        vm.prank(admin);
        market.setTimingConfig(60, 50);
        _startAtPrice(100_000e8);

        _mockPrice(101_000e8);
        _warpToElapsed(1, 30);
        _bet(alice, PricePredictionMarket.Direction.Up, 800e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 200e6, 0);

        uint256 upPrice =
            market.quoteSharePriceBps(1, PricePredictionMarket.Direction.Up, 101_000e8, 0);
        uint256 downPrice =
            market.quoteSharePriceBps(1, PricePredictionMarket.Direction.Down, 101_000e8, 0);

        assertEq(upPrice, 11_800);
        assertEq(downPrice, 9_700);

        (,, uint256 smallAverage,) = market.previewBet(PricePredictionMarket.Direction.Down, 10e6);
        (,, uint256 largeAverage, uint256 largeShares) =
            market.previewBet(PricePredictionMarket.Direction.Down, 500e6);

        assertGt(largeAverage, smallAverage);
        assertLt(largeShares, (500e6 * 10_000) / smallAverage);
        assertApproxEqAbs(smallAverage, 9_712, 1);
    }

    function testDefaultPricingDampensFirstBetPriceImpact() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);

        (uint256 beforePrice, uint256 afterPrice, uint256 averagePrice, uint256 shares) =
            market.previewBet(PricePredictionMarket.Direction.Up, 1e6);

        assertEq(beforePrice, 10_000);
        assertEq(afterPrice, 11_500);
        assertEq(averagePrice, 10_750);
        assertEq(shares, 930_232);
    }

    function testConfigUpdatesApplyOnlyToNextRound() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        _bet(alice, PricePredictionMarket.Direction.Up, 100e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 100e6, 0);

        PricePredictionMarket.PricingConfig memory config = PricePredictionMarket.PricingConfig({
            basePriceBps: 20_000,
            maxTimePremiumBps: 1_000,
            maxTrendAdjustmentBps: 1_000,
            trendMoveCapBps: 500,
            maxPoolImbalanceAdjustmentBps: 1_000,
            minSharePriceBps: 10_000,
            maxSharePriceBps: 40_000
        });
        vm.startPrank(admin);
        market.setCoreReadConfig(1, 4);
        market.setFeeRecipient(carol);
        market.setFeeBps(2_000);
        market.setPricingConfig(config);
        vm.stopPrank();

        uint256 activeRoundPrice =
            market.quoteSharePriceBps(1, PricePredictionMarket.Direction.Up, 100_000e8, 0);
        assertEq(activeRoundPrice, 10_000);

        _warpToElapsed(1, 120);
        vm.prank(operator);
        market.stopBet();

        _mockPriceForIndex(0, 5, 101_000e8);
        _mockPriceForIndex(1, 4, 99_000e8);
        _warpToElapsed(1, 130);
        market.settle();
        market.cleanup(1, 10);

        assertEq(token.balanceOf(feeRecipient), 5e6);
        assertEq(token.balanceOf(carol), 10_000e6);

        _mockPriceForIndex(1, 4, 100_000e8);
        vm.prank(operator);
        market.startRound();
        assertEq(market.roundBtcPerpIndexes(2), 1);
        assertEq(market.roundBtcSzDecimals(2), 4);
        uint256 nextRoundPrice =
            market.quoteSharePriceBps(2, PricePredictionMarket.Direction.Up, 100_000e8, 0);
        assertEq(nextRoundPrice, 20_000);
    }

    function testMinSharesOutProtectsUser() public {
        _startAtPrice(100_000e8);
        _mockPrice(101_000e8);

        (,,, uint256 shares) = market.previewBet(PricePredictionMarket.Direction.Up, 10e6);

        vm.expectRevert(PricePredictionMarket.SlippageExceeded.selector);
        _bet(alice, PricePredictionMarket.Direction.Up, 10e6, shares + 1);
    }

    function testBetRequiresAtLeastOneUsdcReceived() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);

        vm.expectRevert(PricePredictionMarket.InvalidAmount.selector);
        _bet(alice, PricePredictionMarket.Direction.Up, 1e6 - 1, 0);

        token.setTransferFeeBps(1_000);
        vm.expectRevert(PricePredictionMarket.InvalidAmount.selector);
        _bet(alice, PricePredictionMarket.Direction.Up, 1e6, 0);

        vm.expectRevert(PricePredictionMarket.InvalidAmount.selector);
        market.previewBet(PricePredictionMarket.Direction.Up, 1e6 - 1);

        _bet(alice, PricePredictionMarket.Direction.Up, 2e6, 0);
    }

    function testBettingWindowAndSettleTiming() public {
        _startAtPrice(100_000e8);

        _warpToElapsed(1, 119);
        _mockPrice(100_200e8);
        _bet(alice, PricePredictionMarket.Direction.Up, 10e6, 0);

        _warpToElapsed(1, 120);
        vm.expectRevert(PricePredictionMarket.BetWindowClosed.selector);
        _bet(bob, PricePredictionMarket.Direction.Down, 10e6, 0);

        vm.prank(carol);
        market.stopBet();

        _warpToElapsed(1, 129);
        vm.expectRevert(PricePredictionMarket.SettleTooEarly.selector);
        vm.prank(operator);
        market.settle();
    }

    function testUpWinChargesFeeOnlyFromDownPoolAndCleansInBatches() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        _bet(alice, PricePredictionMarket.Direction.Up, 100e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 80e6, 0);
        _bet(carol, PricePredictionMarket.Direction.Up, 40e6, 0);

        _warpToElapsed(1, 120);
        vm.prank(carol);
        market.stopBet();

        _warpToElapsed(1, 130);
        _mockPrice(100_500e8);
        vm.prank(operator);
        market.settle();

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 carolBefore = token.balanceOf(carol);
        uint256 feeBefore = token.balanceOf(feeRecipient);

        market.cleanup(1, 1);
        assertEq(token.balanceOf(feeRecipient), feeBefore);

        market.cleanup(1, 10);

        assertGt(token.balanceOf(alice), aliceBefore);
        assertGt(token.balanceOf(carol), carolBefore);
        assertEq(token.balanceOf(feeRecipient), feeBefore + 4e6);

        (PricePredictionMarket.RoundState state,,,,,,,,,,,,,) = market.rounds(1);
        assertEq(uint256(state), uint256(PricePredictionMarket.RoundState.Cleaned));
    }

    function testDownWinAndDrawRefund() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        _bet(alice, PricePredictionMarket.Direction.Up, 100e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 100e6, 0);

        _warpToElapsed(1, 120);
        vm.prank(operator);
        market.stopBet();

        _warpToElapsed(1, 130);
        _mockPrice(99_500e8);
        vm.prank(operator);
        market.settle();
        market.cleanup(1, 10);

        assertGt(token.balanceOf(bob), token.balanceOf(alice));

        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);
        _bet(alice, PricePredictionMarket.Direction.Up, 20e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 30e6, 0);

        _warpToElapsed(2, 120);
        vm.prank(operator);
        market.stopBet();
        _warpToElapsed(2, 130);
        _mockPrice(100_000e8);
        vm.prank(operator);
        market.settle();
        market.cleanup(2, 10);

        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(bob), bobBefore);
    }

    function testNoWinnerNoContestRefundsAllStake() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        uint256 aliceBefore = token.balanceOf(alice);
        _bet(alice, PricePredictionMarket.Direction.Up, 100e6, 0);

        _warpToElapsed(1, 130);
        _mockPrice(99_000e8);
        market.settle();
        market.cleanup(1, 10);

        (PricePredictionMarket.RoundState state, PricePredictionMarket.Outcome outcome,,,,,,,,,,,,)
        = market.rounds(1);
        assertEq(uint256(state), uint256(PricePredictionMarket.RoundState.Cleaned));
        assertEq(uint256(outcome), uint256(PricePredictionMarket.Outcome.NoContest));
        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function testFeeOnTransferBetAccountingUsesReceivedAmount() public {
        token.setTransferFeeBps(1_000);
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);

        _bet(alice, PricePredictionMarket.Direction.Up, 100e6, 0);

        (,,,,,,, uint256 upPool,, uint256 upShares,,,,) = market.rounds(1);
        assertEq(upPool, 90e6);
        assertEq(upShares, 83_720_930);
        assertEq(token.balanceOf(address(market)), 90e6);
    }

    function testCleanupTransferFailureEscrowsPayoutAndDoesNotBlockRound() public {
        _startAtPrice(100_000e8);
        _mockPrice(100_000e8);
        _bet(alice, PricePredictionMarket.Direction.Up, 100e6, 0);
        _bet(bob, PricePredictionMarket.Direction.Down, 100e6, 0);

        _warpToElapsed(1, 130);
        _mockPrice(101_000e8);
        market.settle();

        token.setBlockedRecipient(alice, true);
        market.cleanup(1, 10);

        (PricePredictionMarket.RoundState state,,,,,,,,,,,,,) = market.rounds(1);
        assertEq(uint256(state), uint256(PricePredictionMarket.RoundState.Cleaned));
        assertGt(market.pendingPayouts(alice), 0);

        token.setBlockedRecipient(alice, false);
        vm.prank(alice);
        market.claimPendingPayout();

        assertEq(market.pendingPayouts(alice), 0);
    }

    function testClampBounds() public {
        vm.prank(admin);
        market.setTimingConfig(60, 50);
        _startAtPrice(100_000e8);
        _warpToElapsed(1, 49);

        uint256 upPrice =
            market.quoteSharePriceBps(1, PricePredictionMarket.Direction.Up, 200_000e8, 0);
        uint256 downPrice =
            market.quoteSharePriceBps(1, PricePredictionMarket.Direction.Down, 200_000e8, 0);

        assertEq(upPrice, 12_725);
        assertEq(downPrice, 9_725);

        _bet(alice, PricePredictionMarket.Direction.Up, 9_000e6, 0);
        upPrice = market.quoteSharePriceBps(1, PricePredictionMarket.Direction.Up, 200_000e8, 0);
        assertEq(upPrice, 14_225);
    }

    function testSimulationSearchesForTwoSidedLockProfit() public {
        for (uint256 seed = 1; seed <= 32; ++seed) {
            setUp();
            _startAtPrice(100_000e8);

            uint256 upBackground = ((seed * 37) % 900 + 50) * 1e6;
            uint256 downBackground = ((seed * 71) % 900 + 50) * 1e6;
            uint256 elapsed = (seed * 13) % 119;
            uint256 currentPrice = (98_000 + ((seed * 211) % 4_000)) * 1e8;
            uint256 upBet = ((seed * 17) % 400 + 10) * 1e6;
            uint256 downBet = ((seed * 29) % 400 + 10) * 1e6;

            _mockPrice(currentPrice);
            _warpToElapsed(1, elapsed);
            _bet(alice, PricePredictionMarket.Direction.Up, upBackground, 0);
            _bet(bob, PricePredictionMarket.Direction.Down, downBackground, 0);
            _bet(arb, PricePredictionMarket.Direction.Up, upBet, 0);
            _bet(arb, PricePredictionMarket.Direction.Down, downBet, 0);

            uint256 cost = upBet + downBet;
            (uint256 upPayout, uint256 downPayout) = _arbPotentialPayouts(1);

            assertFalse(upPayout > cost && downPayout > cost);
        }
    }

    function _startAtPrice(uint256 priceE8) private {
        _mockPrice(priceE8);
        vm.prank(operator);
        market.startRound();
    }

    function _warpToElapsed(uint256 roundId, uint256 elapsed) private {
        (,, uint256 startTime,,,,,,,,,,,) = market.rounds(roundId);
        vm.warp(startTime + elapsed);
    }

    function _bet(
        address user,
        PricePredictionMarket.Direction direction,
        uint256 amount,
        uint256 minSharesOut
    ) private {
        vm.prank(user);
        market.bet(direction, amount, minSharesOut);
    }

    function _mintAndApprove(address user, uint256 amount) private {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(market), type(uint256).max);
    }

    function _mockPrice(uint256 priceE8) private {
        _mockPriceForIndex(BTC_PERP_INDEX, BTC_SZ_DECIMALS, priceE8);
    }

    function _mockPriceForIndex(uint32 perpIndex, uint8 szDecimals, uint256 priceE8) private {
        uint256 rawPrice = (priceE8 * (10 ** (6 - szDecimals))) / 1e8;
        vm.mockCall(CORE_READ, abi.encode(uint256(perpIndex)), abi.encode(rawPrice));
    }

    function _arbPotentialPayouts(uint256 roundId)
        private
        view
        returns (uint256 upPayout, uint256 downPayout)
    {
        (,,,,,,, uint256 upPool, uint256 downPool, uint256 upShares, uint256 downShares,,,) =
            market.rounds(roundId);
        (,, uint256 arbUpShares, uint256 arbDownShares) = market.positions(roundId, arb);

        uint256 upFee = (downPool * market.feeBps()) / 10_000;
        uint256 downFee = (upPool * market.feeBps()) / 10_000;
        upPayout = ((upPool + downPool - upFee) * arbUpShares) / upShares;
        downPayout = ((upPool + downPool - downFee) * arbDownShares) / downShares;
    }
}
