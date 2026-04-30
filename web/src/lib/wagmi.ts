import { http, createConfig } from "wagmi";
import { injected, metaMask } from "wagmi/connectors";
import { config, hyperEvm } from "./config";

export const wagmiConfig = createConfig({
  chains: [hyperEvm],
  connectors: [
    metaMask({
      dappMetadata: {
        name: "PricePrediction",
        url: typeof window !== "undefined" ? window.location.origin : "https://priceprediction.app",
      },
    }),
    injected(),
  ],
  transports: {
    [hyperEvm.id]: http(config.rpcUrl),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
