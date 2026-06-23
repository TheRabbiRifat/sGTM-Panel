'use client';
import * as React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  LayoutDashboard,
  Server,
  CreditCard,
  Users,
  Settings,
  History,
  Network,
} from 'lucide-react';
import { cn } from '@/lib/utils';

const NAV = [
  { href: '/dashboard',  label: 'Dashboard',  icon: LayoutDashboard },
  { href: '/services',   label: 'Services',   icon: Server },
  { href: '/nodes',      label: 'Nodes',      icon: Network },
  { href: '/plans',      label: 'Plans',      icon: CreditCard },
  { href: '/users',      label: 'Users',      icon: Users },
  { href: '/audit-logs', label: 'Audit Logs', icon: History },
  { href: '/settings',   label: 'Settings',   icon: Settings },
];

export function Sidebar() {
  const pathname = usePathname();
  return (
    <aside className="w-60 border-r bg-card h-screen sticky top-0 flex flex-col">
      <div className="p-6 border-b">
        <div className="text-xl font-bold tracking-tight text-primary">
          Hostaffin
        </div>
        <div className="text-xs text-muted-foreground mt-1">sGTM Platform · Admin</div>
      </div>
      <nav className="flex-1 p-3 space-y-1">
        {NAV.map((item) => {
          const active = pathname.startsWith(item.href);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                'flex items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors',
                active
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
              )}
            >
              <Icon className="h-4 w-4" />
              {item.label}
            </Link>
          );
        })}
      </nav>
      <div className="p-4 text-xs text-muted-foreground border-t">
        v0.1.0 · {new Date().getFullYear()}
      </div>
    </aside>
  );
}