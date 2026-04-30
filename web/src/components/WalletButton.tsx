import { LogOut, PlugZap, Wallet } from "lucide-react";
import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { HYPEREVM_CHAIN_ID } from "../lib/config";
import { compactAddress } from "../lib/format";

export function WalletButton() {
  const { address, isConnected, chainId } = useAccount();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const wrongChain = isConnected && chainId !== HYPEREVM_CHAIN_ID;

  if (!isConnected) {
    return (
      <button
        className="button primary"
        disabled={isPending}
        onClick={() => connect({ connector: connectors[0] })}
        type="button"
      >
        <Wallet size={18} />
        Connect wallet
      </button>
    );
  }

  if (wrongChain) {
    return (
      <button
        className="button warning"
        disabled={isSwitching}
        onClick={() => switchChain({ chainId: HYPEREVM_CHAIN_ID })}
        type="button"
      >
        <PlugZap size={18} />
        Switch to HyperEVM
      </button>
    );
  }

  return (
    <button className="button ghost" onClick={() => disconnect()} type="button">
      <LogOut size={18} />
      {compactAddress(address)}
    </button>
  );
}

