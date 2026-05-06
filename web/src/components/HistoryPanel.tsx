import { ArrowDown, ArrowUp, Clock3 } from "lucide-react";
import { formatUnits } from "viem";
import { directionLabels, useUserBetHistory, type AccountState } from "../lib/hooks";
import { formatNumber, formatToken } from "../lib/format";

function formatRoi(value?: number) {
  if (value === undefined || !Number.isFinite(value)) return "--";
  const prefix = value > 0 ? "+" : "";
  return `${prefix}${formatNumber(value / 100, 2)}%`;
}

export function HistoryPanel({ account }: { account: AccountState }) {
  const history = useUserBetHistory(account.address);
  const rows = history.rows.slice(0, 10);

  return (
    <section className="panel">
      <div className="panel-title">
        <div>
          <p>History</p>
          <h2>Your recent bets</h2>
        </div>
        <span className="pill">{rows.length} visible</span>
      </div>

      <div className="history-list">
        {rows.length === 0 ? (
          <div className="empty">
            <Clock3 size={18} />
            No wallet betting history found yet.
          </div>
        ) : (
          rows.map((row) => {
            const event = row.event;
            const direction = Number(event.args.direction ?? 0) as 0 | 1;
            return (
              <div className="history-row" key={`${event.transactionHash}-${event.logIndex}`}>
                <span className={direction === 0 ? "history-icon up" : "history-icon down"}>
                  {direction === 0 ? <ArrowUp size={16} /> : <ArrowDown size={16} />}
                </span>
                <div>
                  <strong>
                    {directionLabels[direction]} on round #{event.args.roundId?.toString()}
                  </strong>
                  <small>{event.transactionHash}</small>
                </div>
                <dl className="history-stats">
                  <div>
                    <dt>Amount</dt>
                    <dd>{formatNumber(Number(formatUnits(event.args.amount ?? 0n, history.decimals)))} USDC</dd>
                  </div>
                  <div>
                    <dt>Result</dt>
                    <dd>{row.statusLabel}</dd>
                  </div>
                  <div>
                    <dt>ROI</dt>
                    <dd>{formatRoi(row.roiBps)}</dd>
                  </div>
                  <div>
                    <dt>Payout</dt>
                    <dd>{formatToken(row.payout, history.decimals)} USDC</dd>
                  </div>
                </dl>
              </div>
            );
          })
        )}
      </div>
    </section>
  );
}
