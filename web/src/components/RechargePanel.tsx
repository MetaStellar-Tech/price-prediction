import { useMemo, useState } from "react";
import { ArrowRightLeft, Check, ExternalLink, Fuel, Send } from "lucide-react";
import { formatUnits } from "viem";
import { HYPE_GAS_RESERVE, HYPE_TOP_UP_USDC } from "../lib/config";
import { buildHypeTopUpPlan, buildUsdcBridgePlan, coreBalance } from "../lib/hyperliquid";
import { useAccountState, useHyperliquidExchange, useMids } from "../lib/hooks";
import { formatNumber } from "../lib/format";

export function RechargePanel() {
  const account = useAccountState();
  const mids = useMids();
  const [usdcAmount, setUsdcAmount] = useState("25");
  const [submittedStep, setSubmittedStep] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const evmHype = Number(formatUnits(account.hypeBalance ?? 0n, 18));
  const needsHype = account.isConnected && evmHype < HYPE_GAS_RESERVE;
  const hypeMid = mids.data ? Number(mids.data.HYPE ?? mids.data["HYPE/USDC"]) : undefined;
  const exchange = useHyperliquidExchange();
  const estimatedHypeAmount = hypeMid && hypeMid > 0 ? (HYPE_TOP_UP_USDC / (hypeMid * 1.03)).toFixed(5) : "";
  const plan = useMemo(
    () => (needsHype ? buildHypeTopUpPlan(hypeMid) : buildUsdcBridgePlan(usdcAmount)),
    [hypeMid, needsHype, usdcAmount],
  );
  const coreUsdc = coreBalance(account.coreBalances, "USDC")?.available ?? 0;

  async function executeStep(kind: string, index: number) {
    try {
      setSubmittedStep(kind);
      setStatus("Waiting for wallet signature.");
      if (needsHype && index === 0) {
        await exchange.buyHypeWithUsdc(HYPE_TOP_UP_USDC, hypeMid);
        setStatus("HYPE buy order submitted. Confirm fill before sending HYPE to EVM.");
      } else if (needsHype) {
        await exchange.spotSendToHyperEvm("HYPE", estimatedHypeAmount);
        setStatus("HYPE Core-to-EVM transfer submitted.");
      } else {
        await exchange.spotSendToHyperEvm("USDC", usdcAmount);
        setStatus("USDC Core-to-EVM transfer submitted.");
      }
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Recharge action failed.");
    }
  }

  return (
    <section className="panel">
      <div className="panel-title">
        <div>
          <p>Recharge</p>
          <h2>{needsHype ? "Fuel HyperEVM first" : "Move USDC to HyperEVM"}</h2>
        </div>
        <span className="pill">{needsHype ? `${HYPE_TOP_UP_USDC} USDC HYPE top-up` : "Core spot send"}</span>
      </div>

      {!needsHype ? (
        <label className="field">
          <span>USDC amount</span>
          <input
            inputMode="decimal"
            min="0"
            onChange={(event) => setUsdcAmount(event.target.value)}
            value={usdcAmount}
          />
          <small>Core USDC available: {formatNumber(coreUsdc)}</small>
        </label>
      ) : null}

      <div className="flow-list">
        {plan.map((step, index) => (
          <div className="flow-step" key={`${step.kind}-${index}`}>
            <div className="flow-icon">
              {step.kind === "buy-hype" ? <Fuel size={18} /> : <Send size={18} />}
            </div>
            <div>
              <strong>{step.title}</strong>
              <p>{step.description}</p>
              <code>{JSON.stringify(step.actionPreview)}</code>
            </div>
            <button
              className="button compact"
              disabled={!exchange.isReady || exchange.isLoading}
              onClick={() => executeStep(`${step.kind}-${index}`, index)}
              type="button"
            >
              {submittedStep === `${step.kind}-${index}` ? <Check size={16} /> : <ArrowRightLeft size={16} />}
              {submittedStep === `${step.kind}-${index}` ? "Submitted" : "Sign"}
            </button>
          </div>
        ))}
      </div>
      {status ? <p className="callout">{status}</p> : null}

      <a
        className="external-note"
        href="https://app.hyperliquid.xyz"
        rel="noreferrer"
        target="_blank"
      >
        <ExternalLink size={16} />
        Wallet signatures are reviewed step-by-step before exchange submission.
      </a>
    </section>
  );
}
