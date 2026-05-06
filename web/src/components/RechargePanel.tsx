import { useMemo, useState } from "react";
import { ArrowRightLeft, Check, ExternalLink, Fuel, Send } from "lucide-react";
import { formatUnits } from "viem";
import { HYPE_GAS_RESERVE, HYPE_TOP_UP_USDC } from "../lib/config";
import {
  buildHypeTopUpPlan,
  buildUsdcBridgePlan,
  coreBalance,
  formatSpotSizeFloor,
  spotMidPrice,
  spotTokenSizeDecimals,
} from "../lib/hyperliquid";
import { useHyperliquidExchange, useMids, useSpotMeta, type AccountState } from "../lib/hooks";
import { formatNumber } from "../lib/format";

function rechargeErrorMessage(error: unknown): string {
  const parts: string[] = [];
  let current = error;
  while (current instanceof Error) {
    if (current.message && !parts.includes(current.message)) parts.push(current.message);
    current = (current as Error & { cause?: unknown }).cause;
  }
  if (
    typeof current === "object" &&
    current &&
    "message" in current &&
    typeof (current as { message?: unknown }).message === "string"
  ) {
    const message = (current as { message: string }).message;
    if (!parts.includes(message)) parts.push(message);
  }
  return parts.join(" | ") || "Recharge action failed.";
}

export function RechargePanel({ account }: { account: AccountState }) {
  const mids = useMids();
  const spotMeta = useSpotMeta();
  const [usdcAmount, setUsdcAmount] = useState("25");
  const [submittedStep, setSubmittedStep] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const evmHype = Number(formatUnits(account.hypeBalance ?? 0n, 18));
  const needsHype = account.isConnected && evmHype < HYPE_GAS_RESERVE;
  const hypeMid = spotMidPrice(spotMeta.data, mids.data, "HYPE", "USDC");
  const hypeSzDecimals = spotTokenSizeDecimals(spotMeta.data, "HYPE");
  const exchange = useHyperliquidExchange();
  const estimatedHypeAmount =
    hypeMid && hypeMid > 0 && hypeSzDecimals !== undefined
      ? (formatSpotSizeFloor(HYPE_TOP_UP_USDC / (hypeMid * 1.03), hypeSzDecimals) ?? "")
      : "";
  const plan = useMemo(
    () => (needsHype ? buildHypeTopUpPlan(hypeMid, hypeSzDecimals) : buildUsdcBridgePlan(usdcAmount)),
    [hypeMid, hypeSzDecimals, needsHype, usdcAmount],
  );
  const coreUsdc = coreBalance(account.coreBalances, "USDC")?.available ?? 0;
  const signDisabled = Boolean(exchange.disabledReason);

  async function executeStep(kind: string, index: number) {
    try {
      setSubmittedStep(kind);
      setStatus(
        needsHype && index === 0
          ? "Approving or rotating a local Hyperliquid API wallet, then signing the order locally."
          : "Waiting for wallet signature.",
      );
      if (needsHype && index === 0) {
        await exchange.buyHypeWithUsdc(HYPE_TOP_UP_USDC, hypeMid);
        setStatus("HYPE buy order submitted. Confirm fill before sending HYPE to EVM.");
      } else if (needsHype) {
        await exchange.sendAssetToHyperEvm("HYPE", estimatedHypeAmount);
        setStatus("HYPE Core-to-EVM transfer submitted.");
      } else {
        await exchange.sendAssetToHyperEvm("USDC", usdcAmount);
        setStatus("USDC Core-to-EVM transfer submitted.");
      }
    } catch (error) {
      setStatus(rechargeErrorMessage(error));
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
              disabled={signDisabled}
              onClick={() => executeStep(`${step.kind}-${index}`, index)}
              title={exchange.disabledReason}
              type="button"
            >
              {submittedStep === `${step.kind}-${index}` ? <Check size={16} /> : <ArrowRightLeft size={16} />}
              {submittedStep === `${step.kind}-${index}` ? "Submitted" : "Sign"}
            </button>
          </div>
        ))}
      </div>
      {exchange.disabledReason ? <p className="inline-muted">{exchange.disabledReason}</p> : null}
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
