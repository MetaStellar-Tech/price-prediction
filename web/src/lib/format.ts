import { formatUnits, type Address } from "viem";

export function compactAddress(address?: Address) {
  if (!address) return "Not connected";
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

export function formatToken(value?: bigint, decimals = 6, digits = 2) {
  if (value === undefined) return "--";
  return formatNumber(Number(formatUnits(value, decimals)), digits);
}

export function formatUsd(value?: number | null, digits = 2) {
  if (value === undefined || value === null || Number.isNaN(value)) return "--";
  return `$${formatNumber(value, digits)}`;
}

export function formatNumber(value?: number, digits = 2) {
  if (value === undefined || Number.isNaN(value)) return "--";
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits: digits,
    minimumFractionDigits: value !== 0 && Math.abs(value) < 1 ? Math.min(digits, 4) : 0,
  }).format(value);
}

export function formatPriceE8(value?: bigint) {
  if (value === undefined || value === 0n) return "--";
  return formatUsd(Number(formatUnits(value, 8)), 2);
}

export function secondsUntil(timestamp?: bigint) {
  if (!timestamp) return 0;
  return Math.max(0, Number(timestamp) - Math.floor(Date.now() / 1000));
}

export function formatCountdown(seconds: number) {
  if (seconds <= 0) return "Ready";
  const minutes = Math.floor(seconds / 60);
  const rest = seconds % 60;
  return `${minutes}m ${rest.toString().padStart(2, "0")}s`;
}

