'use client';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { Card, CardContent } from '@/components/ui/card';
import { fmtNumber } from '@/lib/utils';

export default function PlansPage() {
  const { data, isLoading } = useQuery({ queryKey: ['plans'], queryFn: api.plans });
  const plans = data?.items ?? [];
  if (isLoading) return <div>Loading…</div>;
  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Plans</h1>
      <div className="grid md:grid-cols-3 gap-4">
        {plans.map((p) => (
          <Card key={p.id}>
            <CardContent className="p-6 space-y-2">
              <div className="text-2xl font-bold">{p.name}</div>
              <div className="text-sm text-muted-foreground font-mono">{p.slug}</div>
              <ul className="text-sm space-y-1 mt-3">
                <li>CPU: {p.cpu_limit} vCPU</li>
                <li>RAM: {fmtNumber(p.ram_limit_mb)} MB</li>
                <li>Requests: {fmtNumber(p.request_limit)}/mo</li>
                <li>Bandwidth: {fmtNumber(p.bandwidth_limit_gb)} GB/mo</li>
              </ul>
              <div className="text-xl font-bold mt-3">
                ${(p.price_cents / 100).toFixed(2)} <span className="text-sm font-normal text-muted-foreground">/mo</span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}