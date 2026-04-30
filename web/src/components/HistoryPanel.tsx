import { ArrowDown, ArrowUp, Clock3 } from "lucide-react";
import { formatUnits } from "viem";
import { directionLabels, useAccountState, useMarketState } from "../lib/hooks";
import { formatNumber } from "../lib/format";

export function HistoryPanel() {
  const account = useAccountState();
  const market = useMarketState(account.address);
  const rows = [...market.userEvents].reverse().slice(0, 8);

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
          rows.map((event) => {
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
                <b>{formatNumber(Number(formatUnits(event.args.amount ?? 0n, market.decimals)))} USDC</b>
              </div>
            );
          })
        )}
      </div>
    </section>
  );
}

