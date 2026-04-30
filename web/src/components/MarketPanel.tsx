import { useCallback, useEffect, useMemo, useState } from "react";
import { Activity, ArrowDown, ArrowUp, Coins, Loader2, Scale, Timer } from "lucide-react";
import { formatUnits } from "viem";
import { DEFAULT_SLIPPAGE_BPS } from "../lib/config";
import {
  directionLabels,
  outcomeLabels,
  roundStateLabels,
  useAccountState,
  useBetFlow,
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

export function MarketPanel() {
  const account = useAccountState();
  const market = useMarketState(account.address);
  const mids = useMids();
  const [direction, setDirection] = useState<0 | 1>(0);
  const [amount, setAmount] = useState("10");
  const [message, setMessage] = useState<string | null>(null);
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
  const totalPool = (round?.[7] ?? 0n) + (round?.[8] ?? 0n);
  const upPool = Number(formatUnits(round?.[7] ?? 0n, market.decimals));
  const downPool = Number(formatUnits(round?.[8] ?? 0n, market.decimals));
  const upShare = totalPool > 0n ? (upPool / (upPool + downPool)) * 100 : 0;
  const btcMid = mids.data ? Number(mids.data.BTC ?? mids.data["BTC/USDC"]) : undefined;
  const stopCountdown = formatCountdown(secondsUntil(round?.[3] as bigint | undefined));
  const settleCountdown = formatCountdown(secondsUntil(round?.[4] as bigint | undefined));

  const position = useMemo(() => {
    const data = market.position;
    return {
      upStake: data?.[0],
      downStake: data?.[1],
      upShares: data?.[2],
      downShares: data?.[3],
    };
  }, [market.position]);

  async function onBet() {
    try {
      setMessage(null);
      await flow.placeBet(direction, amount, account.allowance);
      setMessage("Transaction submitted. Waiting for HyperEVM confirmation.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Bet failed.");
    }
  }

  async function onSettle() {
    try {
      setMessage(null);
      await flow.settle();
      setMessage("Settle submitted. Waiting for confirmation.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Settle failed.");
    }
  }

  async function onClaim() {
    try {
      setMessage(null);
      await flow.claimPendingPayout();
      setMessage("Claim submitted. Waiting for confirmation.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Claim failed.");
    }
  }

  return (
    <section className="panel market-panel">
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
          <small>Default slippage: {DEFAULT_SLIPPAGE_BPS / 100}%</small>
        </label>
        <button className="button primary wide" disabled={flow.isPending || !account.isConnected} onClick={onBet} type="button">
          {flow.isPending ? <Loader2 className="spin" size={18} /> : null}
          Bet {directionLabels[direction]}
        </button>
      </div>

      <div className="position-strip">
        <span>Your Up stake: {formatToken(position.upStake, market.decimals)} USDC</span>
        <span>Your Down stake: {formatToken(position.downStake, market.decimals)} USDC</span>
        <span>Your Up shares: {formatToken(position.upShares, market.decimals)}</span>
        <span>Your Down shares: {formatToken(position.downShares, market.decimals)}</span>
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
