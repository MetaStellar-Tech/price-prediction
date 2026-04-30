import { Coins, Gauge, ShieldCheck, WalletCards } from "lucide-react";
import { useAccountState } from "../lib/hooks";
import { HYPEREVM_CHAIN_ID } from "../lib/config";
import { coreBalance } from "../lib/hyperliquid";
import { compactAddress, formatNumber, formatToken } from "../lib/format";
import { MetricCard } from "./MetricCard";

export function AccountPanel() {
  const account = useAccountState();
  const coreUsdc = coreBalance(account.coreBalances, "USDC");
  const coreHype = coreBalance(account.coreBalances, "HYPE");
  const isReady = account.isConnected && account.chainId === HYPEREVM_CHAIN_ID;
  const accountMode = account.accountAbstraction ?? "unknown";

  return (
    <section className="panel">
      <div className="panel-title">
        <div>
          <p>Wallet</p>
          <h2>{compactAddress(account.address)}</h2>
        </div>
        <span className={isReady ? "pill ok" : "pill warn"}>
          {isReady ? "HyperEVM ready" : "Connect chain 999"}
        </span>
      </div>

      <div className="metrics-grid">
        <MetricCard
          label="EVM HYPE"
          value={formatToken(account.hypeBalance, 18, 4)}
          detail="Gas balance"
          tone="warn"
        />
        <MetricCard
          label={`EVM ${account.token.symbol}`}
          value={formatToken(account.evmStakeBalance, account.token.decimals)}
          detail="Available for betting"
        />
        <MetricCard
          label="Allowance"
          value={formatToken(account.allowance, account.token.decimals)}
          detail="Market approval"
        />
        <MetricCard
          label="Pending payout"
          value={formatToken(account.pendingPayout, account.token.decimals)}
          detail="Claimable escrow"
          tone="up"
        />
      </div>

      <div className="asset-strip">
        <div>
          <Coins size={18} />
          <span>Core USDC</span>
          <strong>{formatNumber(coreUsdc?.available)}</strong>
        </div>
        <div>
          <Gauge size={18} />
          <span>Core HYPE</span>
          <strong>{formatNumber(coreHype?.available, 4)}</strong>
        </div>
        <div>
          <ShieldCheck size={18} />
          <span>HL mode</span>
          <strong>{accountMode}</strong>
        </div>
      </div>

      <div className="core-balances">
        <div className="mini-title">
          <WalletCards size={17} />
          <strong>HyperCore spot balances</strong>
        </div>
        {account.coreBalancesError ? (
          <p className="inline-error">
            {(account.coreBalancesError as Error).message ?? "Unable to read HyperCore balances."}
          </p>
        ) : null}
        {account.coreBalances && account.coreBalances.length > 0 ? (
          <div className="balance-table">
            {account.coreBalances.map((balance) => (
              <div className="balance-row" key={balance.coin}>
                <span>{balance.coin}</span>
                <strong>{formatNumber(balance.available, balance.available < 1 ? 4 : 2)}</strong>
                <small>Total {formatNumber(balance.total, balance.total < 1 ? 4 : 2)}</small>
              </div>
            ))}
          </div>
        ) : (
          <p className="inline-muted">No HyperCore spot assets found for this wallet.</p>
        )}
      </div>
    </section>
  );
}
