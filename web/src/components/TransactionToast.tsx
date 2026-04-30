import { CheckCircle2, Loader2, XCircle } from "lucide-react";
import type { Hash } from "viem";

type TransactionToastStatus = "pending" | "success" | "error";

export type TransactionToastState = {
  hash?: Hash;
  title: string;
  detail: string;
  status: TransactionToastStatus;
};

export function TransactionToast({ toast }: { toast: TransactionToastState | null }) {
  if (!toast) return null;

  const Icon =
    toast.status === "success" ? CheckCircle2 : toast.status === "error" ? XCircle : Loader2;
  const hashLabel = toast.hash ? `${toast.hash.slice(0, 10)}...${toast.hash.slice(-8)}` : undefined;

  return (
    <aside className={`tx-toast ${toast.status}`} role="status" aria-live="polite">
      <span className="tx-toast-icon">
        <Icon className={toast.status === "pending" ? "spin" : ""} size={18} />
      </span>
      <div>
        <strong>{toast.title}</strong>
        <p>{toast.detail}</p>
        {hashLabel ? <small>{hashLabel}</small> : null}
      </div>
    </aside>
  );
}
