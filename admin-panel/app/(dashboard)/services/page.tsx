'use client';
import Link from 'next/link';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { Card, CardContent } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { fmtDate } from '@/lib/utils';

const statusVariant: any = {
  active: 'success',
  suspended: 'warning',
  failed: 'destructive',
  pending: 'secondary',
  provisioning: 'secondary',
  terminated: 'outline',
};

export default function ServicesPage() {
  const { data, isLoading, error } = useQuery({ queryKey: ['services'], queryFn: api.services });
  if (isLoading) return <div>Loading services…</div>;
  if (error) return <div className="text-red-500">Failed to load services.</div>;

  const services = data?.items ?? [];
  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Services</h1>
      <Card>
        <CardContent className="p-0">
          <table className="w-full text-sm">
            <thead className="border-b text-muted-foreground">
              <tr>
                <th className="text-left p-3">Service</th>
                <th className="text-left p-3">Status</th>
                <th className="text-left p-3">Edge Hostname</th>
                <th className="text-left p-3">Plan</th>
                <th className="text-left p-3">Created</th>
              </tr>
            </thead>
            <tbody>
              {services.map((s) => (
                <tr key={s.id} className="border-b hover:bg-muted/40">
                  <td className="p-3">
                    <Link href={`/services/${s.id}`} className="text-primary hover:underline">
                      {s.id.slice(0, 8)}
                    </Link>
                    <div className="text-xs text-muted-foreground">WHMCS #{s.whmcs_service_id}</div>
                  </td>
                  <td className="p-3"><Badge variant={statusVariant[s.status] ?? 'outline'}>{s.status}</Badge></td>
                  <td className="p-3 font-mono text-xs">{s.edge_hostname}</td>
                  <td className="p-3">{s.plan_id.slice(0, 8)}</td>
                  <td className="p-3 text-xs">{fmtDate(s.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {services.length === 0 && <div className="p-6 text-muted-foreground">No services yet.</div>}
        </CardContent>
      </Card>
    </div>
  );
}