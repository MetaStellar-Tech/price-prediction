import { useEffect, useMemo, useRef } from "react";
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
import { config } from "./config";
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
    query: { refetchInterval: 10_000 },
  });

  const roundId = currentRoundId.data ?? 0n;
  const enabledRound = roundId > 0n;

  const roundRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "rounds",
    args: [roundId],
    query: { enabled: enabledRound, refetchInterval: 10_000 },
  });
  const participantCountRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "participantCount",
    args: [roundId],
    query: { enabled: enabledRound, refetchInterval: 10_000 },
  });
  const latestBtcPriceRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "latestBtcPriceE8",
    query: { enabled: enabledRound, refetchInterval: 10_000 },
  });
  const positionRead = useReadContract({
    address: config.marketAddress,
    abi: marketAbi,
    functionName: "positions",
    args: [roundId, address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: enabledRound && Boolean(address), refetchInterval: 10_000 },
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
    refetchInterval: 12_000,
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
    refetchInterval: 20_000,
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
    refetchInterval: 10_000,
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
  const receipt = useWaitForTransactionReceipt({ hash });
  const handledHash = useRef<Hash | undefined>();

  async function placeBet(direction: 0 | 1, amount: string, allowance?: bigint) {
    const parsed = parseUnits(amount || "0", token.decimals);
    if (parsed <= 0n) throw new Error("Enter a positive amount.");
    if ((allowance ?? 0n) < parsed) {
      await writeContractAsync({
        address: config.stakeTokenAddress,
        abi: erc20Abi,
        functionName: "approve",
        args: [config.marketAddress, parsed],
      });
    }

    const previewClient = await import("wagmi/actions").then((mod) => mod.readContract);
    const { wagmiConfig } = await import("./wagmi");
    const preview = await previewClient(wagmiConfig, {
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "previewBet",
      args: [direction, parsed],
    });
    const minSharesOut = (preview[3] * 99n) / 100n;

    const txHash = await writeContractAsync({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "bet",
      args: [direction, parsed, minSharesOut],
    });
    return txHash;
  }

  async function settle() {
    return writeContractAsync({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "settle",
    });
  }

  async function claimPendingPayout() {
    return writeContractAsync({
      address: config.marketAddress,
      abi: marketAbi,
      functionName: "claimPendingPayout",
    });
  }

  useEffect(() => {
    if (receipt.isSuccess && hash && handledHash.current !== hash) {
      handledHash.current = hash;
      onDone();
    }
  }, [hash, onDone, receipt.isSuccess]);

  return {
    hash: hash as Hash | undefined,
    isPending: isPending || receipt.isLoading,
    isSuccess: receipt.isSuccess,
    error,
    placeBet,
    settle,
    claimPendingPayout,
  };
}
