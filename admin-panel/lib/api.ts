// Browser-side typed fetchers for the Control Plane API.
// Token is kept in an HttpOnly cookie set by /api/auth/login on the server side.

const CP_URL = process.env.NEXT_PUBLIC_CONTROL_PLANE_URL || '';

export type Service = {
  id: string;
  whmcs_service_id: number;
  whmcs_client_id: number;
  plan_id: string;
  node_id?: string;
  status: 'pending' | 'provisioning' | 'active' | 'suspended' | 'terminated' | 'failed';
  edge_hostname: string;
  overage: boolean;
  created_at: string;
};

export type Plan = {
  id: string;
  name: string;
  slug: string;
  cpu_limit: number;
  ram_limit_mb: number;
  request_limit: number;
  bandwidth_limit_gb: number;
  price_cents: number;
  currency: string;
};

export type Node = {
  id: string;
  hostname: string;
  region?: string;
  status: 'online' | 'offline' | 'draining' | 'maintenance' | 'disabled';
  total_cpu?: number;
  total_ram_mb?: number;
  used_cpu: number;
  used_ram_mb: number;
  container_count: number;
  last_heartbeat?: string;
  is_edge: boolean;
};

export type Loader = {
  id: string;
  service_id: string;
  loader_id: string;
  version: number;
  mode: 'live' | 'preview';
  is_active: boolean;
  hit_count: number;
  sri_hash?: string;
  created_at: string;
};

export type CookieExtension = {
  id: string;
  service_id: string;
  cookie_name: string;
  vendor_url: string;
  new_lifetime_s: number;
  same_site: string;
  secure: boolean;
  http_only: boolean;
  is_active: boolean;
  hit_count: number;
};

async function cpFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const url = CP_URL ? `${CP_URL}${path}` : path;
  const res = await fetch(url, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
    credentials: 'include',
    cache: 'no-store',
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API ${res.status}: ${body}`);
  }
  return res.json();
}

export const api = {
  login: (email: string, password: string) =>
    cpFetch<{ access_token: string; user_id: string; email: string; role: string }>(
      '/api/auth/login',
      { method: 'POST', body: JSON.stringify({ email, password }) }
    ),
  services: () => cpFetch<{ items: Service[] }>('/api/services'),
  service: (id: string) => cpFetch<Service>(`/api/services/${id}`),
  serviceUsage: (id: string) =>
    cpFetch<{ days: any[]; month: any }>(`/api/services/${id}/usage`),
  plans: () => cpFetch<{ items: Plan[] }>('/api/plans'),
  nodes: () => cpFetch<{ items: Node[] }>('/api/nodes'),
  loaders: (serviceId: string) =>
    cpFetch<{ items: Loader[] }>(`/api/services/${serviceId}/loaders`),
  regenerateLoader: (loaderId: string) =>
    cpFetch<{ old_id: string; new_id: string }>(
      `/api/loaders/${loaderId}/regenerate`,
      { method: 'POST' }
    ),
  cookieExtensions: (serviceId: string) =>
    cpFetch<{ items: CookieExtension[] }>(`/api/services/${serviceId}/cookie-extensions`),
  createCookieExtension: (serviceId: string, body: Partial<CookieExtension>) =>
    cpFetch<CookieExtension>(`/api/services/${serviceId}/cookie-extensions`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  deleteCookieExtension: (id: string) =>
    cpFetch<{ ok: boolean }>(`/api/cookie-extensions/${id}`, { method: 'DELETE' }),
  testCookieExtension: (id: string) =>
    cpFetch<any>(`/api/cookie-extensions/${id}/test`, { method: 'POST' }),
  serviceAction: (id: string, action: 'restart' | 'suspend' | 'unsuspend' | 'terminate') =>
    cpFetch<{ ok: boolean }>(`/api/services/${id}/${action}`, { method: 'POST' }),
};