'use client';
import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { api, Loader } from '@/lib/api';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Copy, RotateCw } from 'lucide-react';
import { fmtNumber } from '@/lib/utils';

export function LoaderManager({ serviceId }: { serviceId: string }) {
  const qc = useQueryClient();
  const { data, isLoading } = useQuery({
    queryKey: ['loaders', serviceId],
    queryFn: () => api.loaders(serviceId),
  });

  const regen = useMutation({
    mutationFn: (loaderId: string) => api.regenerateLoader(loaderId),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['loaders', serviceId] }),
  });

  const loaders = data?.items ?? [];
  if (isLoading) return <div>Loading loaders…</div>;

  return (
    <div className="space-y-4">
      <p className="text-sm text-muted-foreground">
        Custom Loader is a gated first-party JavaScript snippet served from the customer's
        own sGTM container. The snippet only fires after the configured trigger and dispatches
        a payload into the customer's GTM container.
      </p>

      {loaders.length === 0 && <div className="text-muted-foreground">No loaders yet.</div>}

      {loaders.map((l) => (
        <Card key={l.id}>
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="text-lg font-mono">{l.loader_id}</CardTitle>
                <CardDescription>
                  Mode: {l.mode} · Version {l.version} · {fmtNumber(l.hit_count)} hits
                </CardDescription>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant={l.is_active ? 'success' : 'outline'}>
                  {l.is_active ? 'Active' : 'Inactive'}
                </Badge>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => regen.mutate(l.loader_id)}
                  disabled={regen.isPending}
                >
                  <RotateCw className="h-4 w-4 mr-1" />
                  Regenerate
                </Button>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-3">
            <Snippet
              text={`<script async src="https://${loaders[0]?.loader_id ? '<edge-hostname>' : ''}/loader.js?id=${l.loader_id}" data-loader-id="${l.loader_id}"></script>`}
            />
            {l.sri_hash && (
              <div className="text-xs text-muted-foreground">
                SRI: <code className="bg-muted px-1 py-0.5 rounded">{l.sri_hash}</code>
              </div>
            )}
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

function Snippet({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="relative">
      <pre className="bg-muted p-3 rounded text-xs overflow-x-auto">{text}</pre>
      <Button
        size="sm"
        variant="ghost"
        className="absolute top-2 right-2"
        onClick={async () => {
          await navigator.clipboard.writeText(text);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        }}
      >
        <Copy className="h-3 w-3 mr-1" /> {copied ? 'Copied' : 'Copy'}
      </Button>
    </div>
  );
}