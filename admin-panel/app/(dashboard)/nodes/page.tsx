'use client';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { fmtNumber } from '@/lib/utils';

const variant: any = {
  online: 'success',
  offline: 'destructive',
  draining: 'warning',
  maintenance: 'warning',
  disabled: 'outline',
};

export default function NodesPage() {
  const { data, isLoading } = useQuery({ queryKey: ['nodes'], queryFn: api.nodes });
  const nodes = data?.items ?? [];
  if (isLoading) return <div>Loading…</div>;

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Nodes</h1>
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
        {nodes.map((n) => (
          <Card key={n.id}>
            <CardContent className="p-6 space-y-2">
              <div className="flex items-center justify-between">
                <div className="font-mono font-semibold">{n.hostname}</div>
                <Badge variant={variant[n.status]}>{n.status}</Badge>
              </div>
              <div className="text-xs text-muted-foreground">
                Edge: {n.is_edge ? 'yes' : 'no'} · {n.region ?? 'no region'}
              </div>
              <div className="grid grid-cols-3 gap-2 text-sm">
                <Stat label="CPU" value={`${fmtNumber(n.used_cpu)}/${fmtNumber(n.total_cpu)}`} />
                <Stat label="RAM MB" value={`${fmtNumber(n.used_ram_mb)}/${fmtNumber(n.total_ram_mb)}`} />
                <Stat label="Containers" value={fmtNumber(n.container_count)} />
              </div>
            </CardContent>
          </Card>
        ))}
        {nodes.length === 0 && <div className="text-muted-foreground">No nodes registered.</div>}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="font-mono">{value}</div>
    </div>
  );
}