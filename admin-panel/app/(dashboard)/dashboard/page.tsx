'use client';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { fmtBytes, fmtNumber } from '@/lib/utils';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Legend,
} from 'recharts';

const PIE_COLORS = ['hsl(142 76% 36%)', 'hsl(217 91% 60%)', 'hsl(38 92% 50%)'];

export default function DashboardPage() {
  const { data: servicesData } = useQuery({ queryKey: ['services'], queryFn: api.services });
  const { data: plansData } = useQuery({ queryKey: ['plans'], queryFn: api.plans });
  const { data: nodesData } = useQuery({ queryKey: ['nodes'], queryFn: api.nodes });

  const services = servicesData?.items ?? [];
  const plans = plansData?.items ?? [];
  const nodes = nodesData?.items ?? [];

  const counts = services.reduce(
    (acc, s) => ({ ...acc, [s.status]: (acc[s.status] ?? 0) + 1 }),
    {} as Record<string, number>
  );

  const mrr = plans.length
    ? plans.reduce((sum, p) => sum + (p.price_cents * (counts[p.slug] ?? 0)), 0) / 100
    : 0;

  const planDistribution = plans.map((p) => ({
    name: p.name,
    value: services.filter((s) => s.plan_id === p.id).length,
  }));

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Dashboard</h1>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader>
            <CardDescription>Active services</CardDescription>
            <CardTitle>{counts.active ?? 0}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Suspended</CardDescription>
            <CardTitle>{counts.suspended ?? 0}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>Failed</CardDescription>
            <CardTitle>{counts.failed ?? 0}</CardTitle>
          </CardHeader>
        </Card>
        <Card>
          <CardHeader>
            <CardDescription>MRR (USD)</CardDescription>
            <CardTitle>${mrr.toFixed(2)}</CardTitle>
          </CardHeader>
        </Card>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Plan distribution</CardTitle>
          </CardHeader>
          <CardContent>
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie data={planDistribution} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80}>
                  {planDistribution.map((_, i) => (
                    <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                  ))}
                </Pie>
                <Tooltip />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Nodes</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {nodes.length === 0 && <p className="text-muted-foreground text-sm">No nodes registered yet.</p>}
            {nodes.map((n) => (
              <div key={n.id} className="flex items-center justify-between border rounded-md p-3">
                <div>
                  <div className="font-medium">{n.hostname}</div>
                  <div className="text-xs text-muted-foreground">
                    CPU {fmtNumber(n.used_cpu)}/{fmtNumber(n.total_cpu)} · RAM {fmtNumber(n.used_ram_mb)}/{fmtNumber(n.total_ram_mb)} MB
                  </div>
                </div>
                <Badge variant={n.status === 'online' ? 'success' : n.status === 'offline' ? 'destructive' : 'warning'}>
                  {n.status}
                </Badge>
              </div>
            ))}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}