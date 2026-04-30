import type { Address } from "viem";
import { config, HYPE_SYSTEM_ADDRESS } from "./config";

export type CoreBalance = {
  coin: string;
  total: number;
  hold: number;
  available: number;
};

type SpotBalance = {
  coin: string;
  total: string;
  hold: string;
};

type SpotClearinghouseState = {
  balances?: SpotBalance[];
};

type AllMids = Record<string, string>;

type SpotMeta = {
  universe: {
    tokens: number[];
    name: string;
    index: number;
    isCanonical: boolean;
  }[];
  tokens: {
    name: string;
    index: number;
    tokenId: `0x${string}`;
    szDecimals: number;
    weiDecimals: number;
    evmContract: { address: Address; evm_extra_wei_decimals: number } | null;
  }[];
};

async function postHyperliquid<T>(url: string, body: unknown): Promise<T> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const details = await response.text();
    throw new Error(`Hyperliquid request failed: ${response.status} ${details}`);
  }

  return (await response.json()) as T;
}

export async function getSpotBalances(address?: Address): Promise<CoreBalance[]> {
  if (!address) return [];
  const state = await postHyperliquid<SpotClearinghouseState>(config.hyperliquidInfoUrl, {
    type: "spotClearinghouseState",
    user: address,
  });

  return (state.balances ?? []).map((balance) => {
    const total = Number(balance.total);
    const hold = Number(balance.hold);
    return {
      coin: balance.coin,
      total,
      hold,
      available: Math.max(0, total - hold),
    };
  });
}

export async function getAllMids(): Promise<AllMids> {
  return postHyperliquid<AllMids>(config.hyperliquidInfoUrl, { type: "allMids" });
}

export async function getSpotMeta(): Promise<SpotMeta> {
  return postHyperliquid<SpotMeta>(config.hyperliquidInfoUrl, { type: "spotMeta" });
}

export async function getUserAbstraction(address?: Address): Promise<string | null> {
  if (!address) return null;
  return postHyperliquid<string | null>(config.hyperliquidInfoUrl, {
    type: "userAbstraction",
    user: address,
  });
}

export function coreBalance(balances: CoreBalance[] | undefined, coin: string) {
  return balances?.find((balance) => balance.coin.toUpperCase() === coin.toUpperCase());
}

export function spotTokenIdentifier(meta: SpotMeta | undefined, coin: string) {
  const token = meta?.tokens.find((item) => item.name.toUpperCase() === coin.toUpperCase());
  if (!token) return coin;
  return `${token.name}:${token.tokenId}`;
}

export function spotUniverseAsset(meta: SpotMeta | undefined, baseCoin: string, quoteCoin: string) {
  const base = meta?.tokens.find((item) => item.name.toUpperCase() === baseCoin.toUpperCase());
  const quote = meta?.tokens.find((item) => item.name.toUpperCase() === quoteCoin.toUpperCase());
  if (!base || !quote) return undefined;

  const universe = meta?.universe.find(
    (item) => item.tokens.includes(base.index) && item.tokens.includes(quote.index),
  );
  return universe ? 10_000 + universe.index : undefined;
}

export function spotMidPrice(
  meta: SpotMeta | undefined,
  mids: AllMids | undefined,
  baseCoin: string,
  quoteCoin: string,
) {
  if (!mids) return undefined;
  const named = mids[baseCoin] ?? mids[`${baseCoin}/${quoteCoin}`];
  if (named) return Number(named);

  const base = meta?.tokens.find((item) => item.name.toUpperCase() === baseCoin.toUpperCase());
  const quote = meta?.tokens.find((item) => item.name.toUpperCase() === quoteCoin.toUpperCase());
  const universe = meta?.universe.find(
    (item) => base && quote && item.tokens.includes(base.index) && item.tokens.includes(quote.index),
  );
  if (!universe) return undefined;
  const indexed = mids[`@${universe.index}`];
  return indexed ? Number(indexed) : undefined;
}

export function hyperEvmSystemAddressForSpotToken(meta: SpotMeta | undefined, coin: string) {
  if (coin.toUpperCase() === "HYPE") return HYPE_SYSTEM_ADDRESS;
  const token = meta?.tokens.find((item) => item.name.toUpperCase() === coin.toUpperCase());
  if (!token) return undefined;
  const suffix = BigInt(token.index).toString(16).padStart(40, "0");
  return `0x${suffix}` as Address;
}

export type RechargeStepStatus = "idle" | "ready" | "needs-signature" | "submitted" | "confirmed";

export type RechargeAction =
  | {
      kind: "buy-hype";
      title: "Buy HYPE on HyperCore";
      description: string;
      actionPreview: Record<string, unknown>;
      status: RechargeStepStatus;
    }
  | {
      kind: "send-asset";
      title: "Transfer asset to HyperEVM";
      description: string;
      actionPreview: Record<string, unknown>;
      status: RechargeStepStatus;
    };

export function buildHypeTopUpPlan(hypeMid: number | undefined): RechargeAction[] {
  const buySize = hypeMid && hypeMid > 0 ? 2 / hypeMid : undefined;
  return [
    {
      kind: "buy-hype",
      title: "Buy HYPE on HyperCore",
      description: "Market-buy roughly 2 USDC of HYPE on Hyperliquid spot HYPE/USDC.",
      actionPreview: {
        type: "order",
        grouping: "na",
        orders: [
          {
            coin: "HYPE/USDC",
            is_buy: true,
            sz: buySize ? buySize.toFixed(5) : "quote:2 USDC",
            limit_px: "market protected by wallet confirmation",
            order_type: { limit: { tif: "Ioc" } },
            reduce_only: false,
          },
        ],
      },
      status: "ready",
    },
    {
      kind: "send-asset",
      title: "Transfer asset to HyperEVM",
      description: `Send HYPE from HyperCore spot to the HyperEVM system address ${HYPE_SYSTEM_ADDRESS}.`,
      actionPreview: {
        type: "sendAsset",
        token: "HYPE",
        sourceDex: "spot",
        destinationDex: "spot",
        destination: HYPE_SYSTEM_ADDRESS,
        amount: buySize ? buySize.toFixed(5) : "bought HYPE amount",
      },
      status: "ready",
    },
  ];
}

export function buildUsdcBridgePlan(amount: string): RechargeAction[] {
  return [
    {
      kind: "send-asset",
      title: "Transfer asset to HyperEVM",
      description: "Send Core USDC to the HyperEVM linked system route for the connected wallet.",
      actionPreview: {
        type: "sendAsset",
        token: "USDC",
        sourceDex: "spot",
        destinationDex: "spot",
        destination: "USDC HyperEVM system address from Hyperliquid token metadata",
        amount: amount || "0",
      },
      status: "ready",
    },
  ];
}

export async function submitHyperliquidAction(action: Record<string, unknown>) {
  return postHyperliquid<unknown>(config.hyperliquidExchangeUrl, action);
}
