'use client';
import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, CookieExtension } from '@/lib/api';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Trash2, FlaskConical, Plus } from 'lucide-react';
import { fmtNumber } from '@/lib/utils';

export function CookieExtensions({ serviceId }: { serviceId: string }) {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['cookie-extensions', serviceId],
    queryFn: () => api.cookieExtensions(serviceId),
  });

  const create = useMutation({
    mutationFn: (b: Partial<CookieExtension>) => api.createCookieExtension(serviceId, b),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['cookie-extensions', serviceId] }),
  });
  const remove = useMutation({
    mutationFn: (id: string) => api.deleteCookieExtension(id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['cookie-extensions', serviceId] }),
  });
  const test = useMutation({ mutationFn: (id: string) => api.testCookieExtension(id) });

  const cookies = data?.items ?? [];
  if (isLoading) return <div>Loading cookie extensions…</div>;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          Cookie Extension rewrites third-party tracking cookies as first-party cookies
          on the customer's own domain, surviving Safari ITP / Firefox ETP and many ad-blockers.
        </p>
        <AddCookieDialog onCreate={(b) => create.mutate(b)} pending={create.isPending} />
      </div>

      {cookies.length === 0 && <div className="text-muted-foreground">No cookie extensions yet.</div>}

      <div className="grid gap-3">
        {cookies.map((c) => (
          <Card key={c.id}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div>
                  <CardTitle className="text-base font-mono">{c.cookie_name}</CardTitle>
                  <CardDescription>
                    Lifetime: {fmtNumber(c.new_lifetime_s)}s · SameSite {c.c.SameSite ?? c.same_site} ·{' '}
                    {c.secure ? 'Secure' : 'Insecure'} · {c.http_only ? 'HttpOnly' : 'JS-readable'}
                  </CardDescription>
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant={c.is_active ? 'success' : 'outline'}>{c.is_active ? 'Active' : 'Inactive'}</Badge>
                  <Badge variant="secondary">{fmtNumber(c.hit_count)} hits</Badge>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={async () => {
                      const r = await test.mutateAsync(c.id);
                      alert(JSON.stringify(r, null, 2));
                    }}
                  >
                    <FlaskConical className="h-4 w-4 mr-1" /> Test
                  </Button>
                  <Button
                    size="sm"
                    variant="destructive"
                    onClick={() => remove.mutate(c.id)}
                    disabled={remove.isPending}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="text-xs text-muted-foreground">Vendor URL:</div>
              <pre className="bg-muted p-2 rounded text-xs overflow-x-auto mt-1">{c.vendor_url}</pre>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

function AddCookieDialog({
  onCreate,
  pending,
}: {
  onCreate: (b: Partial<CookieExtension>) => void;
  pending: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [lifetime, setLifetime] = useState(34190000);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button><Plus className="h-4 w-4 mr-1" /> Add Cookie Extension</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Add Cookie Extension</DialogTitle>
          <DialogDescription>
            Maps a third-party cookie to a first-party cookie on the customer's domain.
            Lifetime is clamped to 395 days (Chrome cap).
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Cookie name</Label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="_ga" />
          </div>
          <div>
            <Label>Vendor URL</Label>
            <Input value={url} onChange={(e) => setUrl(e.target.value)} placeholder="https://www.google-analytics.com/..." />
          </div>
          <div>
            <Label>Lifetime (seconds)</Label>
            <Input
              type="number"
              value={lifetime}
              onChange={(e) => setLifetime(parseInt(e.target.value || '0', 10))}
            />
            <p className="text-xs text-muted-foreground mt-1">
              Default: 34190000 (395 days). {lifetime > 34190000 ? 'Will be clamped.' : ''}
            </p>
          </div>
        </div>
        <DialogFooter>
          <Button
            disabled={!name || !url || pending}
            onClick={() => {
              onCreate({
                cookie_name: name,
                vendor_url: url,
                new_lifetime_s: lifetime,
                same_site: 'Lax',
                secure: true,
                http_only: false,
                is_active: true,
              } as any);
              setOpen(false);
            }}
          >
            Create
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}