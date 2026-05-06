import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  ArrowDown,
  ArrowUp,
  Coins,
  Loader2,
  RefreshCw,
  Scale,
  Timer,
} from "lucide-react";
import { formatUnits } from "viem";
import { DEFAULT_SLIPPAGE_BPS } from "../lib/config";
import {
  directionLabels,
  outcomeLabels,
  roundStateLabels,
  useAccountState,
  useBetFlow,
  useBetPreview,
  useMarketState,
  useMids,
} from "../lib/hooks";
import {
  formatCountdown,
  formatNumber,
  formatPriceE8,
  formatToken,
  secondsUntil,
} from "../lib/format";
import { MetricCard } from "./MetricCard";
import { TransactionToast, type TransactionToastState } from "./TransactionToast";

function marketActionErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("InvalidState") || message.includes("0xbaf3f0f7")) {
    return "Betting is not open for the current round. Wait for the next Betting round.";
  }
  if (message.includes("BetWindowClosed") || message.includes("0x2749efd4")) {
    return "The betting window for this round has closed.";
  }
  if (message.includes("InvalidAmount") || message.includes("0x2c5211c6")) {
    return "Enter a positive bet amount.";
  }
  if (message.includes("SlippageExceeded")) {
    return "Final quote was below your slippage limit. Refresh the quote or choose a wider limit.";
  }
  if (message.toLowerCase().includes("rate limited")) {
    return "The HyperEVM RPC is rate limiting contract simulation right now. Wait a few seconds and retry; the app now avoids extra pre-submit calls where possible.";
  }
  return message || "Market action failed.";
}

const BPS = 10_000n;
const SLIPPAGE_OPTIONS_BPS = [DEFAULT_SLIPPAGE_BPS, 1_000, 500] as const;

function formatSignedPercentBps(value?: number) {
  if (value === undefined || !Number.isFinite(value)) return "--";
  const prefix = value > 0 ? "+" : "";
  return `${prefix}${formatNumber(value / 100, 2)}%`;
}

function formatSignedTokenDelta(value?: bigint, decimals = 6) {
  if (value === undefined) return "--";
  const prefix = value >= 0n ? "+" : "-";
  const magnitude = value >= 0n ? value : -value;
  return `${prefix}${formatToken(magnitude, decimals, 2)} USDC`;
}

function estimateWinningPayout(
  round: NonNullable<ReturnType<typeof useMarketState>["round"]> | undefined,
  direction: 0 | 1,
  amount?: bigint,
  shares?: bigint,
  feeBps?: bigint,
) {
  if (!round || amount === undefined || shares === undefined || feeBps === undefined) return undefined;
  const upPoolAfter = round[7] + (direction === 0 ? amount : 0n);
  const downPoolAfter = round[8] + (direction === 1 ? amount : 0n);
  const upSharesAfter = round[9] + (direction === 0 ? shares : 0n);
  const downSharesAfter = round[10] + (direction === 1 ? shares : 0n);
  const winnerShares = direction === 0 ? upSharesAfter : downSharesAfter;
  if (winnerShares === 0n) return undefined;
  const loserPool = direction === 0 ? downPoolAfter : upPoolAfter;
  const fee = (loserPool * feeBps) / BPS;
  return ((upPoolAfter + downPoolAfter - fee) * shares) / winnerShares;
}

export function MarketPanel() {
  const account = useAccountState();
  const market = useMarketState(account.address);
  const mids = useMids();
  const [direction, setDirection] = useState<0 | 1>(0);
  const [amount, setAmount] = useState("1");
  const [slippageBps, setSlippageBps] = useState<number>(DEFAULT_SLIPPAGE_BPS);
  const [message, setMessage] = useState<string | null>(null);
  const [toast, setToast] = useState<TransactionToastState | null>(null);
  const [, setClockTick] = useState(0);
  useEffect(() => {
    const timer = window.setInterval(() => setClockTick((tick) => tick + 1), 1_000);
    return () => window.clearInterval(timer);
  }, []);
  const refetchAfterTx = useCallback(() => {
    account.refetch();
    market.refetch();
  }, [account, market]);
  const flow = useBetFlow(refetchAfterTx);
  const round = market.round;
  const roundState = Number(round?.[0] ?? 0);
  const outcome = Number(round?.[1] ?? 0);
  const canSettle =
    roundState === 1 || roundState === 2
      ? secondsUntil(round?.[4] as bigint | undefined) === 0
      : false;
  const canPreview = roundState === 1;
  const canQuote = canPreview && secondsUntil(round?.[3] as bigint | undefined) > 0;
  const canBet = account.isConnected && canQuote;
  const upPreview = useBetPreview(0, amount, canPreview);
  const downPreview = useBetPreview(1, amount, canPreview);
  const preview = direction === 0 ? upPreview : downPreview;
  const totalPool = (round?.[7] ?? 0n) + (round?.[8] ?? 0n);
  const upPool = Number(formatUnits(round?.[7] ?? 0n, market.decimals));
  const downPool = Number(formatUnits(round?.[8] ?? 0n, market.decimals));
  const upShare = totalPool > 0n ? (upPool / (upPool + downPool)) * 100 : 0;
  const btcMid = mids.data ? Number(mids.data.BTC ?? mids.data["BTC/USDC"]) : undefined;
  const stopCountdown = formatCountdown(secondsUntil(round?.[3] as bigint | undefined));
  const settleCountdown = formatCountdown(secondsUntil(round?.[4] as bigint | undefined));
  const beforePriceBps = preview.data?.[0];
  const afterPriceBps = preview.data?.[1];
  const priceImpactBps =
    beforePriceBps && afterPriceBps !== undefined
      ? Number(((afterPriceBps - beforePriceBps) * 10_000n) / beforePriceBps)
      : undefined;
  const upPotentialPayout = estimateWinningPayout(
    round,
    0,
    upPreview.parsedAmount,
    upPreview.data?.[3],
    market.roundFeeBps,
  );
  const downPotentialPayout = estimateWinningPayout(
    round,
    1,
    downPreview.parsedAmount,
    downPreview.data?.[3],
    market.roundFeeBps,
  );
  const upPotentialNet =
    upPotentialPayout === undefined || upPreview.parsedAmount === undefined
      ? undefined
      : upPotentialPayout - upPreview.parsedAmount;
  const downPotentialNet =
    downPotentialPayout === undefined || downPreview.parsedAmount === undefined
      ? undefined
      : downPotentialPayout - downPreview.parsedAmount;

  const position = useMemo(() => {
    const data = market.position;
    return {
      upStake: data?.[0],
      downStake: data?.[1],
    };
  }, [market.position]);

  useEffect(() => {
    if (!toast || flow.hash !== toast.hash || toast.status !== "pending") return;
    if (flow.receipt.data?.status === "success") {
      setToast({
        ...toast,
        title: "Transaction confirmed",
        detail: "HyperEVM confirmed the transaction. The market view is refreshing.",
        status: "success",
      });
    } else if (flow.receipt.data?.status === "reverted" || flow.receipt.isError) {
      setToast({
        ...toast,
        title: "Transaction failed",
        detail:
          flow.receipt.error?.message ??
          "HyperEVM confirmed the transaction with a reverted status.",
        status: "error",
      });
    }
  }, [flow.hash, flow.receipt.data?.status, flow.receipt.error, flow.receipt.isError, toast]);

  useEffect(() => {
    if (!toast || toast.status === "pending") return;
    const timer = window.setTimeout(() => setToast(null), 4_500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  function showSubmittedToast(title: string, hash: `0x${string}`) {
    setToast({
      hash,
      title,
      detail: "Transaction submitted. Waiting for HyperEVM confirmation.",
      status: "pending",
    });
  }

  async function onBet() {
    try {
      setMessage(null);
      if (!canBet) {
        setMessage(
          roundState === 1
            ? "The betting window for this round has closed."
            : "Betting is not open for the current round.",
        );
        return;
      }
      const refreshedPreview = preview.data ? undefined : await preview.refetch();
      const shares = preview.data?.[3] ?? refreshedPreview?.data?.[3];
      const hash = await flow.placeBet(direction, amount, account.allowance, slippageBps, shares);
      showSubmittedToast("Bet submitted", hash);
    } catch (error) {
      setMessage(marketActionErrorMessage(error));
    }
  }

  async function onSettle() {
    try {
      setMessage(null);
      const hash = await flow.settle();
      showSubmittedToast("Settle submitted", hash);
    } catch (error) {
      setMessage(marketActionErrorMessage(error));
    }
  }

  async function onClaim() {
    try {
      setMessage(null);
      const hash = await flow.claimPendingPayout();
      showSubmittedToast("Claim submitted", hash);
    } catch (error) {
      setMessage(marketActionErrorMessage(error));
    }
  }

  return (
    <section className="panel market-panel">
      <TransactionToast toast={toast} />
      <div className="panel-title">
        <div>
          <p>Active market</p>
          <h2>BTC next round</h2>
        </div>
        <span className="pill">Round #{market.roundId.toString() || "0"}</span>
      </div>

      <div className="metrics-grid">
        <MetricCard label="State" value={roundStateLabels[roundState] ?? "Unknown"} detail={outcomeLabels[outcome]} />
        <MetricCard label="Total pool" value={`${formatToken(totalPool, market.decimals)} USDC`} detail="Both sides" />
        <MetricCard label="Start price" value={formatPriceE8(round?.[5])} detail="CoreRead snapshot" />
        <MetricCard
          label="Live BTC"
          value={formatPriceE8(market.latestBtcPriceE8)}
          detail={btcMid ? `Info mid ${formatNumber(btcMid)}` : "HyperEVM L1Read"}
        />
      </div>

      <div className="pool-row">
        <div className="side up">
          <div>
            <ArrowUp size={20} />
            <strong>Up</strong>
          </div>
          <b>{formatNumber(upPool)} USDC</b>
          <span>{market.metrics.upCount} bets</span>
        </div>
        <div className="pool-bar" aria-label="Pool split">
          <span style={{ width: `${Number.isFinite(upShare) ? upShare : 50}%` }} />
        </div>
        <div className="side down">
          <div>
            <ArrowDown size={20} />
            <strong>Down</strong>
          </div>
          <b>{formatNumber(downPool)} USDC</b>
          <span>{market.metrics.downCount} bets</span>
        </div>
      </div>

      <div className="status-grid">
        <span>
          <Timer size={16} /> Stop betting: {stopCountdown}
        </span>
        <span>
          <Scale size={16} /> Settle: {settleCountdown}
        </span>
        <span>
          <Coins size={16} /> Wallets: {market.metrics.walletCount}
        </span>
        <span>
          <Activity size={16} /> Bets: {market.metrics.betCount}
        </span>
      </div>

      <div className="trade-box">
        <div className="segmented">
          <button className={direction === 0 ? "active" : ""} onClick={() => setDirection(0)} type="button">
            <ArrowUp size={16} />
            Up
          </button>
          <button className={direction === 1 ? "active" : ""} onClick={() => setDirection(1)} type="button">
            <ArrowDown size={16} />
            Down
          </button>
        </div>
        <label className="field">
          <span>Bet amount</span>
          <input inputMode="decimal" onChange={(event) => setAmount(event.target.value)} value={amount} />
        </label>
        <div className="field">
          <span>Slippage limit</span>
          <div className="segmented compact">
            {SLIPPAGE_OPTIONS_BPS.map((option) => (
              <button
                className={slippageBps === option ? "active" : ""}
                key={option}
                onClick={() => setSlippageBps(option)}
                type="button"
              >
                {option / 100}%
              </button>
            ))}
          </div>
        </div>
        <button className="button primary wide" disabled={flow.isPending || !canBet} onClick={onBet} type="button">
          {flow.isPending ? <Loader2 className="spin" size={18} /> : null}
          Bet {directionLabels[direction]}
        </button>
      </div>

      <div className="quote-panel">
        <div>
          <span>If Up wins</span>
          <strong>{formatToken(upPotentialPayout, market.decimals, 2)} USDC</strong>
          <small>Net {formatSignedTokenDelta(upPotentialNet, market.decimals)}</small>
        </div>
        <div>
          <span>If Down wins</span>
          <strong>{formatToken(downPotentialPayout, market.decimals, 2)} USDC</strong>
          <small>Net {formatSignedTokenDelta(downPotentialNet, market.decimals)}</small>
        </div>
        <div>
          <span>Quote impact</span>
          <strong>{formatSignedPercentBps(priceImpactBps)}</strong>
          <small>{canQuote ? (totalPool === 0n ? "First bet impact included" : "Current pool included") : "Betting locked"}</small>
        </div>
        <button
          className="button ghost icon-button"
          disabled={!canPreview || upPreview.isFetching || downPreview.isFetching}
          onClick={() => {
            void upPreview.refetch();
            void downPreview.refetch();
          }}
          title="Refresh quote"
          type="button"
        >
          <RefreshCw className={upPreview.isFetching || downPreview.isFetching ? "spin" : ""} size={17} />
        </button>
      </div>

      <div className="position-strip">
        <span>Your Up stake: {formatToken(position.upStake, market.decimals)} USDC</span>
        <span>Your Down stake: {formatToken(position.downStake, market.decimals)} USDC</span>
      </div>

      <div className="action-row">
        <button className="button ghost" disabled={!canSettle || flow.isPending} onClick={onSettle} type="button">
          Settle round
        </button>
        <button
          className="button ghost"
          disabled={(account.pendingPayout ?? 0n) === 0n || flow.isPending}
          onClick={onClaim}
          type="button"
        >
          Claim pending payout
        </button>
      </div>
      {message || flow.error ? <p className="callout">{message ?? flow.error?.message}</p> : null}
    </section>
  );
}
