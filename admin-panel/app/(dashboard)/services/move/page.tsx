'use client';
import { useMemo, useState } from 'react';
import Link from 'next/link';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, Service } from '@/lib/api';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { ArrowRightLeft, CheckCircle2, AlertTriangle, Server } from 'lucide-react';
import { fmtDate, fmtNumber } from '@/lib/utils';

export default function BulkMovePage() {
  const qc = useQueryClient();
  const { data: servicesResp } = useQuery({ queryKey: ['services'], queryFn: api.services });
  const { data: nodesResp } = useQuery({ queryKey: ['nodes'], queryFn: api.nodes });

  const services: Service[] = servicesResp?.items ?? [];
  const nodes = nodesResp?.items ?? [];

  const [selectedNode, setSelectedNode] = useState<string>('');
  const [confirmed, setConfirmed] = useState(false);

  const onlineNodes = useMemo(() => nodes.filter((n) => n.status === 'online'), [nodes]);

  // Group services by node
  const grouped = useMemo(() => {
    const map = new Map<string, Service[]>();
    for (const s of services) {
      if (s.status !== 'active' && s.status !== 'provisioning') continue;
      const nid = s.node_id ?? 'unassigned';
      const arr = map.get(nid) ?? [];
      arr.push(s);
      map.set(nid, arr);
    }
    return map;
  }, [services]);

  const target = nodes.find((n) => n.id === selectedNode);
  const totalToMove = target
    ? services.filter((s) => s.node_id && s.node_id !== selectedNode && (s.status === 'active' || s.status === 'provisioning')).length
    : 0;

  const move = useMutation({
    mutationFn: async () => {
      const toMove = services.filter(
        (s) => s.node_id && s.node_id !== selectedNode && (s.status === 'active' || s.status === 'provisioning')
      );
      const results = await Promise.allSettled(
        toMove.map((s) => api.moveService(s.id, selectedNode))
      );
      return { total: toMove.length, results };
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['services'] });
      qc.invalidateQueries({ queryKey: ['nodes'] });
    },
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold">Bulk Move Services</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Admin-only WHM-style transfer tool. Move all active services from any
          node onto one target node — useful when draining a node for maintenance
          or rebalancing after adding capacity.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Choose destination node</CardTitle>
          <CardDescription>
            All active services currently on other nodes will be relocated here.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid md:grid-cols-3 gap-3">
            {onlineNodes.length === 0 && (
              <div className="col-span-3 text-sm text-muted-foreground">
                No online master nodes. Bring one online first.
              </div>
            )}
            {onlineNodes.map((n) => {
              const count = grouped.get(n.id)?.length ?? 0;
              const loadPct = n.total_cpu ? Math.round((n.used_cpu / n.total_cpu) * 100) : 0;
              return (
                <label
                  key={n.id}
                  className={`flex flex-col p-4 rounded border cursor-pointer ${
                    selectedNode === n.id ? 'border-primary bg-primary/5' : 'border-border hover:bg-muted/50'
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <input
                      type="radio"
                      name="target"
                      checked={selectedNode === n.id}
                      onChange={() => { setSelectedNode(n.id); setConfirmed(false); }}
                    />
                    <Server className="h-4 w-4" />
                    <span className="font-mono text-sm">{n.hostname}</span>
                  </div>
                  <div className="text-xs text-muted-foreground mt-2">
                    {n.region ?? 'no region'} · {count} service{count === 1 ? '' : 's'} · CPU {loadPct}%
                  </div>
                </label>
              );
            })}
          </div>
        </CardContent>
      </Card>

      {target && (
        <>
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <ArrowRightLeft className="h-4 w-4" />
                {totalToMove} service{totalToMove === 1 ? '' : 's'} will move to {target.hostname}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <table className="w-full text-sm">
                <thead className="border-b text-muted-foreground">
                  <tr>
                    <th className="text-left p-2">Service</th>
                    <th className="text-left p-2">Edge hostname</th>
                    <th className="text-left p-2">Currently on</th>
                    <th className="text-left p-2">Created</th>
                  </tr>
                </thead>
                <tbody>
                  {services
                    .filter((s) => s.node_id && s.node_id !== selectedNode && (s.status === 'active' || s.status === 'provisioning'))
                    .map((s) => {
                      const cur = nodes.find((n) => n.id === s.node_id);
                      return (
                        <tr key={s.id} className="border-b">
                          <td className="p-2">
                            <Link href={`/services/${s.id}`} className="text-primary hover:underline">
                              {s.id.slice(0, 8)}
                            </Link>
                          </td>
                          <td className="p-2 font-mono text-xs">{s.edge_hostname}</td>
                          <td className="p-2 font-mono text-xs">{cur?.hostname ?? s.node_id?.slice(0, 8) ?? '—'}</td>
                          <td className="p-2 text-xs">{fmtDate(s.created_at)}</td>
                        </tr>
                      );
                    })}
                </tbody>
              </table>
              {totalToMove === 0 && (
                <div className="text-sm text-muted-foreground p-4">
                  All active services are already on {target.hostname}.
                </div>
              )}
            </CardContent>
          </Card>

          <div className="rounded border border-yellow-500/30 bg-yellow-500/5 p-4 text-sm flex gap-2">
            <AlertTriangle className="h-5 w-5 text-yellow-600 flex-shrink-0" />
            <div>
              <strong>Heads up:</strong> each move pauses tracking briefly (≈ 30–90 s per
              service). {totalToMove} services = up to {totalToMove * 60}s of cumulative impact
              if you run them serially. The control plane runs them in parallel.
            </div>
          </div>

          <Card>
            <CardContent className="pt-6 space-y-3">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={confirmed}
                  onChange={(e) => setConfirmed(e.target.checked)}
                />
                I understand tracking will be briefly interrupted on each service.
              </label>
              <Button
                disabled={!confirmed || totalToMove === 0 || move.isPending}
                onClick={() => move.mutate()}
              >
                {move.isPending ? 'Moving…' : `Move ${totalToMove} service${totalToMove === 1 ? '' : 's'} → ${target.hostname}`}
              </Button>

              {move.isSuccess && (
                <div className="rounded border border-green-500/30 bg-green-500/5 p-3 text-sm flex gap-2">
                  <CheckCircle2 className="h-4 w-4 text-green-600 flex-shrink-0 mt-0.5" />
                  <div>
                    Bulk move queued for <strong>{move.data.total}</strong> service
                    {move.data.total === 1 ? '' : 's'}. Refresh the services page in a minute
                    to see the new node assignments.
                    <details className="mt-2 text-xs">
                      <summary className="cursor-pointer text-muted-foreground">
                        Per-service results
                      </summary>
                      <pre className="bg-muted p-2 rounded mt-1 overflow-x-auto">
                        {JSON.stringify(
                          move.data.results.map((r, i) => ({
                            ok: r.status === 'fulfilled',
                            error: r.status === 'rejected' ? (r.reason as Error).message : null,
                          })),
                          null,
                          2
                        )}
                      </pre>
                    </details>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}