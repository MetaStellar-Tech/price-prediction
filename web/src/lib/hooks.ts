import { useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ExchangeClient, HttpTransport } from "@nktkas/hyperliquid";
import type { AbstractWallet } from "@nktkas/hyperliquid/signing";
import { formatPrice } from "@nktkas/hyperliquid/utils";
import {
  parseUnits,
  type Address,
  type GetContractEventsReturnType,
  type Hash,
  type Hex,
} from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import {
  useAccount,
  useBalance,
  useBlockNumber,
  usePublicClient,
  useReadContract,
  useReadContracts,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { erc20Abi, marketAbi } from "./abi";
import {
  APPROVE_GAS_LIMIT,
  BET_GAS_LIMIT,
  CLAIM_PAYOUT_GAS_LIMIT,
  SETTLE_GAS_LIMIT,
  config,
} from "./config";
import {
  getAllMids,
  getExtraAgents,
  getSpotBalances,
  getSpotMeta,
  getUserAbstraction,
  formatSpotSizeFloor,
  hyperEvmSystemAddressForSpotToken,
  spotTokenIdentifier,
  spotTokenSizeDecimals,
  spotUniverseAsset,
} from "./hyperliquid";

export const roundStateLabels = ["None", "Betting", "Betting closed", "Settled", "Cleaned"];
export const outcomeLabels = ["None", "Up", "Down", "Draw", "No contest"];
export const directionLabels = ["Up", "Down"];

type MarketRound = NonNullable<ReturnType<typeof useMarketState>["round"]>;
type BetEvent = GetContractEventsReturnType<typeof marketAbi, "BetPlaced">[number];

export type UserBetHistoryRow = {
  event: BetEvent;
  round?: MarketRound;
  payout?: bigint;
  roiBps?: number;
  statusLabel: string;
};

type HyperliquidTypedDataDomain = {
  name: string;
  version: string;
  chainId: number;
  verifyingContract: `0x${string}`;
};

type TypedDataField = {
  name: string;
  type: string;
};

type Eip1193Provider = {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
};

const HYPERLIQUID_AGENT_KEY_PREFIX = "price-prediction:hyperliquid-agent:";
const HYPERLIQUID_AGENT_NAME = "PricePredict";
const HYPERLIQUID_AGENT_VALID_UNTIL_SKEW_MS = 60_000;
const HYPERLIQUID_AGENT_VALID_FOR_MS = 90 * 24 * 60 * 60 * 1000;
const MARKET_READ_REFETCH_MS = 2_000;
const MARKET_EVENTS_REFETCH_MS = 3_000;
const USER_EVENTS_REFETCH_MS = 5_000;
const MIDS_REFETCH_MS = 3_000;
const BET_PREVIEW_REFETCH_MS = 1_000;

function exchangeApiBaseUrl() {
  return config.hyperliquidExchangeUrl.replace(/\/exchange\/?$/, "");
}

function getOrCreateAgentPrivateKey(owner: Address): Hex {
  if (typeof window === "undefined") return generatePrivateKey();
  const key = `${HYPERLIQUID_AGENT_KEY_PREFIX}${owner.toLowerCase()}`;
  const existing = window.localStorage.getItem(key);
  if (existing?.startsWith("0x")) return existing as Hex;
  const privateKey = generatePrivateKey();
  window.localStorage.setItem(key, privateKey);
  return privateKey;
}

async function providerChainId(provider: Eip1193Provider): Promise<Hex> {
  const chainId = await provider.request({ method: "eth_chainId" });
  if (typeof chainId !== "string" || !chainId.startsWith("0x")) {
    throw new Error("Wallet provider returned an invalid chain id.");
  }
  return chainId as Hex;
}

function providerChainIdNumber(chainId: Hex): number {
  const value = Number(BigInt(chainId));
  if (!Number.isSafeInteger(value)) throw new Error(`Wallet chain id ${chainId} is too large.`);
  return value;
}

function hyperliquidWallet(provider: Eip1193Provider, address: Address): AbstractWallet {
  return {
    getAddress: async () => address,
    provider: {
      getNetwork: async () => ({ chainId: providerChainIdNumber(await providerChainId(provider)) }),
    },
    signTypedData: async (
      domain: HyperliquidTypedDataDomain,
      types: Record<string, TypedDataField[]>,
      message: Record<string, unknown>,
    ) => {
      const chainId = providerChainIdNumber(await providerChainId(provider));
      const primaryType = Object.keys(types)[0];
      if (!primaryType) throw new Error("Hyperliquid typed data is missing a primary type.");
      return provider.request({
        method: "eth_signTypedData_v4",
        params: [
          address,
          JSON.stringify({
            domain: { ...domain, chainId },
            types: {
              EIP712Domain: [
                { name: "name", type: "string" },
                { name: "version", type: "string" },
                { name: "chainId", type: "uint256" },
                { name: "verifyingContract", type: "address" },
              ],
              ...types,
            },
            primaryType,
            message,
          }),
        ],
      }) as Promise<Hex>;
    },
  };
}

export function useTokenMeta() {
  const reads = useReadContracts({
    contracts: [
      {
        address: config.stakeTokenAddress,
        abi: erc20Abi,
        functionName: "decimals",
      },
      {
        address: config.stakeTokenAddress,
        abi: erc20Abi,
        functionName: "symbol",
      },
    ],
  });

  return {
    decimals: reads.data?.[0].result ?? 6,
    symbol: reads.data?.[1].result ?? "USDC",
    isLoading: reads.isLoading,
  };
}

export function useAccountState() {
  const { address, chainId, isConnected } = useAccount();
  const token = useTokenMeta();
  const hypeBalance = useBalance({ address });
  const tokenReads = useReadContracts({
    query: { enabled: Boolean(address) },
    contracts: address
      ? [
          {
            address: config.stakeTokenAddress,
            abi: erc20Abi,
            functionName: "balanceOf",
            args: [address],
          },
          {
            address: config.stakeTokenAddress,
            abi: erc20Abi,
            functionName: "allowance",
            args: [address, config.marketAddress],
          },
          {
            address: config.marketAddress,
            abi: marketAbi,
            functionName: "pendingPayouts",
            args: [address],
          },
        ]
      : [],
  });

  const coreBalances = useQuery({
    queryKey: ["core-balances", address],
    queryFn: () => getSpotBalances(address),
    enabled: Boolean(address),
    refetchInterval: 15_000,
  });
  const accountAbstraction = useQuery({
    queryKey: ["account-abstraction", address],
    queryFn: () => getUserAbstraction(address),
    enabled: Boolean(address),
    refetchInterval: 60_000,
  });

  return {
    address,
    chainId,
    isConnected,
    token,
    hypeBalance: hypeBalance.data?.value,
    evmStakeBalance: tokenReads.data?.[0]?.result,
    allowance: tokenReads.data?.[1]?.result,
    pendingPayout: tokenReads.data?.[2]?.result,
    coreBalances: coreBalances.data,
    coreBalancesError: coreBalances.error,
    accountAbstraction: accountAbstraction.data,
    isLoading:
      hypeBalance.isLoading ||
      tokenReads.isLoading ||
      coreBalances.isLoading ||
      accountAbstraction.isLoading ||
      token.isLoading,
    refetch: () => {
      void hypeBalance.refetch();
      void tokenReads.refetch();
      void coreBalances.refetch();
      void accountAbstraction.refetch();
    },
  };
}

export function useMarketState(address?: Address) {
  const { decimals } = useTokenMeta();
  const publicClient = usePublicClient();
  const block = useBlockNumber({ watch: true });
  const currentRoundId = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "currentRoundId",
    query: { refetchInterval: MARKET_READ_REFETCH_MS },
  });

  const roundId = currentRoundId.data ?? 0n;
  const enabledRound = roundId > 0n;

  const roundRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "rounds",
    args: [roundId],
    query: { enabled: enabledRound, refetchInterval: MARKET_READ_REFETCH_MS },
  });
  const participantCountRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "participantCount",
    args: [roundId],
    query: { enabled: enabledRound, refetchInterval: MARKET_READ_REFETCH_MS },
  });
  const latestBtcPriceRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "latestBtcPriceE8",
    query: { enabled: enabledRound, refetchInterval: MARKET_READ_REFETCH_MS },
  });
  const positionRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "positions",
    args: [roundId, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: enabledRound && Boolean(address), refetchInterval: MARKET_READ_REFETCH_MS },
  });

  const events = useQuery({
    queryKey: ["bet-events", roundId.toString(), block.data?.toString()],
    queryFn: async () => {
      if (!publicClient || !enabledRound) return [];
      return publicClient.getContractEvents({
        address: config.marketAddress,
        abi: marketAbi,
        eventName: "BetPlaced",
        args: { roundId },
        fromBlock: 33_813_039n,
        toBlock: "latest",
      });
    },
    enabled: Boolean(publicClient && enabledRound),
    refetchInterval: MARKET_EVENTS_REFETCH_MS,
  });

  const userEvents = useQuery({
    queryKey: ["user-bet-events", address, block.data?.toString()],
    queryFn: async () => {
      if (!publicClient || !address) return [];
      return publicClient.getContractEvents({
        address: config.marketAddress,
        abi: marketAbi,
        eventName: "BetPlaced",
        args: { user: address },
        fromBlock: 33_813_039n,
        toBlock: "latest",
      });
    },
    enabled: Boolean(publicClient && address),
    refetchInterval: USER_EVENTS_REFETCH_MS,
  });

  const metrics = useMemo(() => summarizeBetEvents(events.data), [events.data]);

  return {
    decimals,
    roundId,
    round: roundRead.data,
    participantCount: participantCountRead.data,
    latestBtcPriceE8: latestBtcPriceRead.data,
    position: positionRead.data,
    events: events.data ?? [],
    userEvents: userEvents.data ?? [],
    metrics,
    isLoading:
      currentRoundId.isLoading ||
      roundRead.isLoading ||
      participantCountRead.isLoading ||
      latestBtcPriceRead.isLoading ||
      positionRead.isLoading,
    refetch: () => {
      void currentRoundId.refetch();
      void roundRead.refetch();
      void participantCountRead.refetch();
      void latestBtcPriceRead.refetch();
      void positionRead.refetch();
      void events.refetch();
      void userEvents.refetch();
    },
  };
}

export function useUserBetHistory(address?: Address) {
  const { decimals } = useTokenMeta();
  const publicClient = usePublicClient();
  const block = useBlockNumber({ watch: true });
  const userEvents = useQuery({
    queryKey: ["user-bet-history-events", address, block.data?.toString()],
    queryFn: async () => {
      if (!publicClient || !address) return [];
      return publicClient.getContractEvents({
        address: config.marketAddress,
        abi: marketAbi,
        eventName: "BetPlaced",
        args: { user: address },
        fromBlock: 33_813_039n,
        toBlock: "latest",
      });
    },
    enabled: Boolean(publicClient && address),
    refetchInterval: USER_EVENTS_REFETCH_MS,
  });

  const roundIds = useMemo(() => {
    const unique = new Map<string, bigint>();
    for (const event of userEvents.data ?? []) {
      const roundId = event.args.roundId;
      if (roundId !== undefined) unique.set(roundId.toString(), roundId);
    }
    return [...unique.values()];
  }, [userEvents.data]);

  const roundReads = useReadContracts({
    contracts: roundIds.map((roundId) => ({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "rounds",
      args: [roundId],
    })),
    query: { enabled: roundIds.length > 0, refetchInterval: USER_EVENTS_REFETCH_MS },
  });

  const roundsById = useMemo(() => {
    const rounds = new Map<string, MarketRound>();
    roundIds.forEach((roundId, index) => {
      const round = roundReads.data?.[index]?.result as MarketRound | undefined;
      if (round) rounds.set(roundId.toString(), round);
    });
    return rounds;
  }, [roundIds, roundReads.data]);

  const rows = useMemo<UserBetHistoryRow[]>(() => {
    return [...(userEvents.data ?? [])]
      .reverse()
      .map((event) => {
        const amount = event.args.amount ?? 0n;
        const shares = event.args.shares ?? 0n;
        const direction = Number(event.args.direction ?? 0);
        const round = event.args.roundId ? roundsById.get(event.args.roundId.toString()) : undefined;
        const state = Number(round?.[0] ?? 0);
        const outcome = Number(round?.[1] ?? 0);
        const payout = estimateBetPayout(round, direction, amount, shares);
        const roiBps = amount > 0n && payout !== undefined ? Number(((payout - amount) * 10_000n) / amount) : undefined;
        const statusLabel =
          state >= 3 ? (outcomeLabels[outcome] ?? "Unknown") : roundStateLabels[state] ?? "Pending";
        return { event, round, payout, roiBps, statusLabel };
      });
  }, [roundsById, userEvents.data]);

  return {
    decimals,
    rows,
    isLoading: userEvents.isLoading || roundReads.isLoading,
    refetch: () => {
      void userEvents.refetch();
      void roundReads.refetch();
    },
  };
}

function estimateBetPayout(
  round: MarketRound | undefined,
  direction: number,
  amount: bigint,
  shares: bigint,
) {
  if (!round) return undefined;
  const state = Number(round[0]);
  const outcome = Number(round[1]);
  if (state < 3) return undefined;
  if (outcome === 3 || outcome === 4) return amount;
  const upPool = round[7];
  const downPool = round[8];
  const upShares = round[9];
  const downShares = round[10];
  const feeAmount = round[11];
  const payoutPool = upPool + downPool - feeAmount;
  if (outcome === 1 && direction === 0 && upShares > 0n) return (payoutPool * shares) / upShares;
  if (outcome === 2 && direction === 1 && downShares > 0n) return (payoutPool * shares) / downShares;
  return 0n;
}

function summarizeBetEvents(events: GetContractEventsReturnType<typeof marketAbi, "BetPlaced"> | undefined) {
  const wallets = new Set<string>();
  let upCount = 0;
  let downCount = 0;
  for (const event of events ?? []) {
    const user = event.args.user;
    if (user) wallets.add(user.toLowerCase());
    if (event.args.direction === 0) upCount += 1;
    if (event.args.direction === 1) downCount += 1;
  }
  return {
    walletCount: wallets.size,
    betCount: events?.length ?? 0,
    upCount,
    downCount,
  };
}

export function useMids() {
  return useQuery({
    queryKey: ["hyperliquid-mids"],
    queryFn: getAllMids,
    refetchInterval: MIDS_REFETCH_MS,
  });
}

export function useSpotMeta() {
  return useQuery({
    queryKey: ["hyperliquid-spot-meta"],
    queryFn: getSpotMeta,
    staleTime: 10 * 60_000,
  });
}

export function useHyperliquidExchange() {
  const { address, connector, isConnected } = useAccount();
  const spotMeta = useSpotMeta();

  const masterExchange = useMemo(() => {
    if (!connector || !address) return undefined;
    return async () => {
      const provider = (await connector.getProvider()) as Eip1193Provider | undefined;
      if (!provider) throw new Error("Wallet provider is not ready yet.");
      return new ExchangeClient({
        transport: new HttpTransport({ apiUrl: exchangeApiBaseUrl() }),
        signatureChainId: () => providerChainId(provider),
        wallet: hyperliquidWallet(provider, address),
      });
    };
  }, [address, connector]);

  const agentExchange = useMemo(() => {
    if (!address) return undefined;
    return () => {
      const agent = privateKeyToAccount(getOrCreateAgentPrivateKey(address));
      return new ExchangeClient({
        transport: new HttpTransport({ apiUrl: exchangeApiBaseUrl() }),
        wallet: agent,
      });
    };
  }, [address]);

  async function sendAssetToHyperEvm(coin: "HYPE" | "USDC", amount: string): Promise<unknown> {
    if (!masterExchange) throw new Error("Connect a wallet before preparing a Core transfer.");
    const client = await masterExchange();
    const destination = hyperEvmSystemAddressForSpotToken(spotMeta.data, coin);
    if (!destination) throw new Error(`Unable to derive ${coin} HyperEVM system address.`);
    return client.sendAsset({
      destination,
      sourceDex: "spot",
      destinationDex: "spot",
      token: spotTokenIdentifier(spotMeta.data, coin),
      amount,
    });
  }

  async function buyHypeWithUsdc(usdcAmount: number, hypeMid?: number): Promise<unknown> {
    if (!masterExchange || !agentExchange || !address) throw new Error("Connect a wallet before preparing a spot order.");
    const asset = spotUniverseAsset(spotMeta.data, "HYPE", "USDC");
    const hypeSzDecimals = spotTokenSizeDecimals(spotMeta.data, "HYPE");
    if (asset === undefined) throw new Error("Unable to derive HYPE/USDC spot asset id.");
    if (hypeSzDecimals === undefined) throw new Error("Unable to derive HYPE spot size decimals.");
    if (!hypeMid || hypeMid <= 0) throw new Error("HYPE mid price is unavailable.");
    const agent = privateKeyToAccount(getOrCreateAgentPrivateKey(address));
    const extraAgents = await getExtraAgents(address);
    const reusableAgent = extraAgents.find(
      (item) =>
        item.address.toLowerCase() === agent.address.toLowerCase() &&
        item.validUntil > Date.now() + HYPERLIQUID_AGENT_VALID_UNTIL_SKEW_MS,
    );
    if (!reusableAgent) {
      const masterClient = await masterExchange();
      await masterClient.approveAgent({
        agentAddress: agent.address,
        agentName: `${HYPERLIQUID_AGENT_NAME} valid_until ${Date.now() + HYPERLIQUID_AGENT_VALID_FOR_MS}`,
      });
    }
    const client = agentExchange();
    const protectedPrice = hypeMid * 1.03;
    const price = formatPrice(protectedPrice, hypeSzDecimals, "spot");
    const size = formatSpotSizeFloor(usdcAmount / protectedPrice, hypeSzDecimals);
    if (!size) throw new Error("HYPE order size is below the minimum supported precision.");
    return client.order({
      orders: [
        {
          a: asset,
          b: true,
          p: price,
          s: size,
          r: false,
          t: { limit: { tif: "Ioc" } },
        },
      ],
      grouping: "na",
    });
  }

  return {
    buyHypeWithUsdc,
    sendAssetToHyperEvm,
    disabledReason: !isConnected
      ? "Connect wallet first"
      : spotMeta.isLoading
        ? "Loading Hyperliquid metadata"
        : !connector
          ? "Wallet connector is not ready yet"
          : undefined,
    isReady: Boolean(masterExchange && agentExchange),
    isLoading: spotMeta.isLoading,
  };
}

export function useBetFlow(onDone: () => void) {
  const token = useTokenMeta();
  const { writeContractAsync, data: hash, isPending, error } = useWriteContract();
  const [submittedHash, setSubmittedHash] = useState<Hash | undefined>();
  const receipt = useWaitForTransactionReceipt({ hash: submittedHash });
  const handledHash = useRef<Hash | undefined>();

  async function placeBet(
    direction: 0 | 1,
    amount: string,
    allowance?: bigint,
    slippageBps = 100,
    quotedShares?: bigint,
  ) {
    const parsed = parseUnits(amount || "0", token.decimals);
    if (parsed <= 0n) throw new Error("Enter a positive amount.");
    if ((allowance ?? 0n) < parsed) {
      await writeContractAsync({
        address: config.stakeTokenAddress,
        abi: erc20Abi,
        functionName: "approve",
        args: [config.marketAddress, parsed],
        gas: APPROVE_GAS_LIMIT,
      });
    }

    const boundedSlippageBps = Math.min(Math.max(Math.trunc(slippageBps), 0), 10_000);
    if (quotedShares === undefined) {
      throw new Error("Quote is temporarily unavailable. Wait a few seconds and refresh the quote.");
    }
    const shares = quotedShares;
    const minSharesOut = (shares * BigInt(10_000 - boundedSlippageBps)) / 10_000n;

    const txHash = await writeContractAsync({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "bet",
      args: [direction, parsed, minSharesOut],
      gas: BET_GAS_LIMIT,
    });
    setSubmittedHash(txHash);
    return txHash;
  }

  async function settle() {
    const txHash = await writeContractAsync({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "settle",
      gas: SETTLE_GAS_LIMIT,
    });
    setSubmittedHash(txHash);
    return txHash;
  }

  async function claimPendingPayout() {
    const txHash = await writeContractAsync({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "claimPendingPayout",
      gas: CLAIM_PAYOUT_GAS_LIMIT,
    });
    setSubmittedHash(txHash);
    return txHash;
  }

  useEffect(() => {
    if (receipt.data && submittedHash && handledHash.current !== submittedHash) {
      handledHash.current = submittedHash;
      onDone();
    }
  }, [onDone, receipt.data, submittedHash]);

  return {
    hash: submittedHash ?? (hash as Hash | undefined),
    isPending: isPending || receipt.isLoading,
    isSuccess: receipt.isSuccess,
    receipt,
    error,
    placeBet,
    settle,
    claimPendingPayout,
  };
}

export function useBetPreview(direction: 0 | 1, amount: string, enabled: boolean) {
  const token = useTokenMeta();
  const parsedAmount = useMemo(() => {
    try {
      const parsed = parseUnits(amount || "0", token.decimals);
      return parsed > 0n ? parsed : undefined;
    } catch {
      return undefined;
    }
  }, [amount, token.decimals]);

  const preview = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "previewBet",
    args: parsedAmount ? [direction, parsedAmount] : undefined,
    query: {
      enabled: enabled && parsedAmount !== undefined,
      refetchInterval: BET_PREVIEW_REFETCH_MS,
    },
  });

  return { ...preview, parsedAmount };
}
