'use client';
import { use } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { fmtBytes, fmtDate, fmtNumber } from '@/lib/utils';
import { LoaderManager } from '@/components/features/loaders';
import { CookieExtensions } from '@/components/features/cookies';

export default function ServiceDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const qc = useQueryClient();
  const { data: service, isLoading } = useQuery({ queryKey: ['service', id], queryFn: () => api.service(id) });
  const { data: usage } = useQuery({ queryKey: ['service-usage', id], queryFn: () => api.serviceUsage(id) });

  const action = useMutation({
    mutationFn: (a: 'restart' | 'suspend' | 'unsuspend' | 'terminate') => api.serviceAction(id, a),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['service', id] }),
  });

  if (isLoading || !service) return <div>Loading…</div>;

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-3xl font-bold">{service.edge_hostname}</h1>
          <p className="text-muted-foreground text-sm">Service ID {service.id} · WHMCS #{service.whmcs_service_id}</p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={() => action.mutate('restart')}>Restart</Button>
          {service.status === 'active'
            ? <Button variant="outline" onClick={() => action.mutate('suspend')}>Suspend</Button>
            : <Button onClick={() => action.mutate('unsuspend')}>Unsuspend</Button>}
          <Button variant="destructive" onClick={() => action.mutate('terminate')}>Terminate</Button>
        </div>
      </div>

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="loaders">Loaders</TabsTrigger>
          <TabsTrigger value="cookies">Cookie Extensions</TabsTrigger>
          <TabsTrigger value="metrics">Metrics</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          <div className="grid md:grid-cols-3 gap-4">
            <Card>
              <CardHeader>
                <CardDescription>Status</CardDescription>
                <CardTitle><Badge>{service.status}</Badge></CardTitle>
              </CardHeader>
            </Card>
            <Card>
              <CardHeader>
                <CardDescription>This month</CardDescription>
                <CardTitle>{fmtNumber(usage?.month?.requests)} req</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="text-xs text-muted-foreground">
                  Bandwidth: {fmtBytes(Number(usage?.month?.bandwidth_b ?? 0))}
                </div>
              </CardContent>
            </Card>
            <Card>
              <CardHeader>
                <CardDescription>Created</CardDescription>
                <CardTitle className="text-base">{fmtDate(service.created_at)}</CardTitle>
              </CardHeader>
            </Card>
          </div>
        </TabsContent>

        <TabsContent value="loaders">
          <LoaderManager serviceId={id} />
        </TabsContent>

        <TabsContent value="cookies">
          <CookieExtensions serviceId={id} />
        </TabsContent>

        <TabsContent value="metrics">
          <Card><CardContent className="p-6 text-muted-foreground">Usage charts render here once enough data is collected.</CardContent></Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}