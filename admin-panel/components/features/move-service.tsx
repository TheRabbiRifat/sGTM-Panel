'use client';
import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, Node, Service } from '@/lib/api';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { ArrowRightLeft, Server, AlertTriangle, CheckCircle2 } from 'lucide-react';
import { fmtNumber } from '@/lib/utils';

/**
 * MoveServiceDialog — admin-only "Transfer Account" tool.
 *
 * Like WHM's transfer-account feature, lets an operator relocate a
 * service container from one master node to another. Useful for:
 *   • rebalancing load across nodes
 *   • draining a node before maintenance
 *   • recovering from a failed node
 *
 * The control plane:
 *   1. Marks the source container for deletion (drains traffic via Traefik)
 *   2. Re-pulls the image on the destination node
 *   3. Re-deploys with the same plan/loader/cookie settings
 *   4. Updates services.node_id
 *   5. Traefik re-discovers via Docker labels (no DNS change)
 */
export function MoveServiceDialog({ service }: { service: Service }) {
  const [open, setOpen] = useState(false);
  const [targetId, setTargetId] = useState<string>('');
  const [confirmText, setConfirmText] = useState('');
  const qc = useQueryClient();

  // Load nodes list
  const { data: nodesResp } = useQuery({
    queryKey: ['nodes-for-move'],
    queryFn: () => api.nodes(),
    enabled: open,
  });
  const allNodes: Node[] = nodesResp?.items ?? [];

  // Online, healthy nodes (excluding current)
  const candidates = useMemo(
    () => allNodes.filter((n) => n.status === 'online' && n.id !== service.node_id),
    [allNodes, service.node_id]
  );
  const currentNode = useMemo(
    () => allNodes.find((n) => n.id === service.node_id),
    [allNodes, service.node_id]
  );

  // Reset state when opening
  useEffect(() => {
    if (open) {
      setTargetId('');
      setConfirmText('');
    }
  }, [open]);

  const move = useMutation({
    mutationFn: (nodeId: string) => api.moveService(service.id, nodeId),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['service', service.id] });
      qc.invalidateQueries({ queryKey: ['services'] });
      qc.invalidateQueries({ queryKey: ['nodes'] });
    },
  });

  const drain = useMutation({
    mutationFn: (id: string) => api.drainNode(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['nodes-for-move'] }),
  });

  const target = candidates.find((n) => n.id === targetId);
  const canMove = target && confirmText === service.edge_hostname && !move.isPending;

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline">
          <ArrowRightLeft className="h-4 w-4 mr-1" />
          Move to another node
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Move sGTM service to a different node</DialogTitle>
          <DialogDescription>
            Like WHM's <em>Transfer Account</em> — moves the container for{' '}
            <code className="text-xs bg-muted px-1 rounded">{service.edge_hostname}</code> to a
            different master node. Tracking on the service will pause briefly
            (≈ 30–90 s) while the image is re-pulled.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {/* Current node */}
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-sm flex items-center gap-2">
                <Server className="h-4 w-4" /> Current node
              </CardTitle>
            </CardHeader>
            <CardContent>
              {currentNode ? (
                <div className="flex items-center justify-between text-sm">
                  <span className="font-mono">{currentNode.hostname}</span>
                  <div className="flex gap-2">
                    <Badge>{currentNode.status}</Badge>
                    <span className="text-xs text-muted-foreground">
                      CPU {fmtNumber(currentNode.used_cpu)}/{fmtNumber(currentNode.total_cpu)} ·
                      RAM {fmtNumber(currentNode.used_ram_mb)}/{fmtNumber(currentNode.total_ram_mb)} MB
                    </span>
                  </div>
                </div>
              ) : (
                <span className="text-xs text-muted-foreground">
                  Not currently assigned (service is being provisioned or no node is online).
                </span>
              )}
            </CardContent>
          </Card>

          {/* Target picker */}
          <div>
            <Label>Destination master node</Label>
            {candidates.length === 0 ? (
              <p className="text-xs text-muted-foreground mt-1">
                No online master nodes available. Bring another node online first.
              </p>
            ) : (
              <div className="space-y-2 mt-2 max-h-56 overflow-y-auto">
                {candidates.map((n) => {
                  const loadPct = n.total_cpu ? Math.round((n.used_cpu / n.total_cpu) * 100) : 0;
                  const ramPct = n.total_ram_mb ? Math.round((n.used_ram_mb / n.total_ram_mb) * 100) : 0;
                  return (
                    <label
                      key={n.id}
                      className={`flex items-center justify-between p-3 rounded border cursor-pointer transition-colors ${
                        targetId === n.id
                          ? 'border-primary bg-primary/5'
                          : 'border-border hover:bg-muted/50'
                      }`}
                    >
                      <div className="flex items-center gap-3">
                        <input
                          type="radio"
                          name="target-node"
                          checked={targetId === n.id}
                          onChange={() => setTargetId(n.id)}
                        />
                        <div>
                          <div className="font-mono text-sm">{n.hostname}</div>
                          <div className="text-xs text-muted-foreground">
                            {n.region ?? 'no region'} · {fmtNumber(n.container_count)} containers
                          </div>
                        </div>
                      </div>
                      <div className="text-right">
                        <div className="text-xs">CPU {loadPct}% · RAM {ramPct}%</div>
                        <Button
                          size="sm"
                          variant="ghost"
                          className="text-xs h-6 px-2"
                          onClick={(e) => {
                            e.preventDefault();
                            if (confirm(`Drain ${n.hostname}? It will stop accepting new containers.`)) {
                              drain.mutate(n.id);
                            }
                          }}
                        >
                          Drain
                        </Button>
                      </div>
                    </label>
                  );
                })}
              </div>
            )}
          </div>

          {/* Confirm */}
          {target && (
            <div className="space-y-2">
              <Label>
                Type <code className="text-xs bg-muted px-1 rounded">{service.edge_hostname}</code> to confirm
              </Label>
              <Input
                value={confirmText}
                onChange={(e) => setConfirmText(e.target.value)}
                placeholder={service.edge_hostname}
              />
            </div>
          )}

          {/* Warnings */}
          <div className="rounded border border-yellow-500/30 bg-yellow-500/5 p-3 text-xs flex gap-2">
            <AlertTriangle className="h-4 w-4 text-yellow-600 flex-shrink-0 mt-0.5" />
            <div className="space-y-1">
              <div>Tracking on this service will pause briefly (≈ 30–90 s).</div>
              <div>
                <strong>Tip:</strong> drain the destination node first if you want zero impact
                on services already running there.
              </div>
            </div>
          </div>

          {/* Result */}
          {move.isSuccess && (
            <div className="rounded border border-green-500/30 bg-green-500/5 p-3 text-sm flex gap-2">
              <CheckCircle2 className="h-4 w-4 text-green-600 flex-shrink-0 mt-0.5" />
              <div>
                <strong>Move queued.</strong> The container is being redeployed on{' '}
                <code className="text-xs">{target?.hostname}</code>. Refresh in a moment to see
                the new node assignment.
              </div>
            </div>
          )}
          {move.isError && (
            <div className="rounded border border-red-500/30 bg-red-500/5 p-3 text-sm">
              <strong>Move failed:</strong> {(move.error as Error).message}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Cancel
          </Button>
          <Button
            disabled={!canMove}
            onClick={() => target && move.mutate(target.id)}
          >
            {move.isPending ? 'Moving…' : `Move to ${target?.hostname ?? '…'}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
