import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function fmtNumber(n: number | undefined | null): string {
  if (n === null || n === undefined) return '0';
  return new Intl.NumberFormat('en-US').format(n);
}

export function fmtBytes(bytes: number | undefined | null): string {
  if (!bytes) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = bytes;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return `${v.toFixed(1)} ${units[i]}`;
}

export function fmtDate(s: string | Date | undefined | null): string {
  if (!s) return '—';
  const d = typeof s === 'string' ? new Date(s) : s;
  return d.toLocaleString();
}