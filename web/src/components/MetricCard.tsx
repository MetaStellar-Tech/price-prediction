import type { ReactNode } from "react";

type MetricCardProps = {
  label: string;
  value: ReactNode;
  detail?: ReactNode;
  tone?: "default" | "up" | "down" | "warn";
};

export function MetricCard({ label, value, detail, tone = "default" }: MetricCardProps) {
  return (
    <div className={`metric ${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      {detail ? <small>{detail}</small> : null}
    </div>
  );
}

