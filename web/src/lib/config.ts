import type { Address } from "viem";

const env = import.meta.env;

export const HYPEREVM_CHAIN_ID = 999;
export const HYPE_SYSTEM_ADDRESS = "0x2222222222222222222222222222222222222222" as Address;
export const HYPE_GAS_RESERVE = 0.02;
export const HYPE_TOP_UP_USDC = 2;
export const DEFAULT_SLIPPAGE_BPS = 500;

export const config = {
  rpcUrl: env.VITE_HYPEREVM_RPC_URL ?? "https://rpc.hyperliquid.xyz/evm",
  wsRpcUrl: env.VITE_HYPEREVM_WS_URL as string | undefined,
  hyperliquidInfoUrl: env.VITE_HYPERLIQUID_INFO_URL ?? "https://api.hyperliquid.xyz/info",
  hyperliquidExchangeUrl:
    env.VITE_HYPERLIQUID_EXCHANGE_URL ?? "https://api.hyperliquid.xyz/exchange",
  marketAddress:
    (env.VITE_MARKET_ADDRESS as Address | undefined) ??
    "0x406661e7AeF968441d53bc9557be3a8FAa92A67B",
  stakeTokenAddress:
    (env.VITE_STAKE_TOKEN_ADDRESS as Address | undefined) ??
    "0xb88339CB7199b77E23DB6E890353E22632Ba630f",
};

export const hyperEvm = {
  id: HYPEREVM_CHAIN_ID,
  name: "Hyperliquid EVM",
  nativeCurrency: {
    decimals: 18,
    name: "HYPE",
    symbol: "HYPE",
  },
  rpcUrls: {
    default: { http: [config.rpcUrl], webSocket: config.wsRpcUrl ? [config.wsRpcUrl] : undefined },
  },
  blockExplorers: {
    default: {
      name: "HyperEVM Explorer",
      url: "https://hyperevmscan.io",
    },
  },
} as const;
