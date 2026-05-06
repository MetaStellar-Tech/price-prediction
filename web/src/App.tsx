import { useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import { ArrowRight, BarChart3, Github, Shield, WalletCards } from "lucide-react";
import { wagmiConfig } from "./lib/wagmi";
import { config } from "./lib/config";
import { useAccountState } from "./lib/hooks";
import { WalletButton } from "./components/WalletButton";
import { AccountPanel } from "./components/AccountPanel";
import { MarketPanel } from "./components/MarketPanel";
import { RechargePanel } from "./components/RechargePanel";
import { HistoryPanel } from "./components/HistoryPanel";
import "./styles/app.css";

const queryClient = new QueryClient();

function Shell() {
  const [view, setView] = useState<"landing" | "app">("landing");

  return (
    <div className="app-shell">
      <header className="topbar">
        <button className="brand" onClick={() => setView("landing")} type="button">
          <span>PP</span>
          <strong>PricePrediction</strong>
        </button>
        <nav>
          <button className={view === "landing" ? "active" : ""} onClick={() => setView("landing")} type="button">
            Home
          </button>
          <button className={view === "app" ? "active" : ""} onClick={() => setView("app")} type="button">
            App
          </button>
        </nav>
        <WalletButton />
      </header>

      {view === "landing" ? <Landing onOpenApp={() => setView("app")} /> : <TradingApp />}
    </div>
  );
}

function Landing({ onOpenApp }: { onOpenApp: () => void }) {
  return (
    <main className="landing">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">HyperEVM prediction market</p>
          <h1>PricePrediction</h1>
          <p>
            Bet on BTC price direction with HyperEVM settlement and HyperCore oracle prices. The
            app connects your wallet directly; no backend account is required.
          </p>
          <div className="hero-actions">
            <button className="button primary large" onClick={onOpenApp} type="button">
              Open app
              <ArrowRight size={18} />
            </button>
            <a className="button ghost large" href="https://hyperliquid.xyz" rel="noreferrer" target="_blank">
              Hyperliquid
            </a>
          </div>
        </div>
        <div className="market-board" aria-label="Live product summary">
          <div className="board-head">
            <BarChart3 size={22} />
            <span>BTC Up / Down</span>
          </div>
          <div className="board-chart">
            <span />
            <span />
            <span />
            <span />
            <span />
            <span />
          </div>
          <div className="board-footer">
            <span>Market</span>
            <strong>{config.marketAddress.slice(0, 8)}...{config.marketAddress.slice(-6)}</strong>
          </div>
        </div>
      </section>

      <section className="landing-band">
        <div>
          <WalletCards size={22} />
          <h2>One wallet surface</h2>
          <p>See HyperCore spot assets, HyperEVM balances, allowance, and pending payouts together.</p>
        </div>
        <div>
          <Shield size={22} />
          <h2>On-chain settlement</h2>
          <p>Rounds settle through the deployed PricePredictionMarket contract on HyperEVM mainnet.</p>
        </div>
        <div>
          <Github size={22} />
          <h2>Pure frontend</h2>
          <p>Designed for Vercel hosting with no custodial key path and no production backend.</p>
        </div>
      </section>
    </main>
  );
}

function TradingApp() {
  const account = useAccountState();

  return (
    <main className="dashboard">
      <div className="dashboard-main">
        <MarketPanel account={account} />
        <HistoryPanel account={account} />
      </div>
      <aside className="dashboard-side">
        <AccountPanel account={account} />
        <RechargePanel account={account} />
      </aside>
    </main>
  );
}

export default function App() {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <Shell />
      </QueryClientProvider>
    </WagmiProvider>
  );
}
