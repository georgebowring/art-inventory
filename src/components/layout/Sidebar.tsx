import { NavLink } from 'react-router-dom';
import {
  LayoutDashboard,
  Image,
  Palette,
  Users,
  Receipt,
  MapPin,
  Calendar,
  FileText,
  Settings,
} from 'lucide-react';
import { cn } from '@/lib/utils';

const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/artworks', label: 'Artworks', icon: Image },
  { to: '/artists', label: 'Artists', icon: Palette },
  { to: '/contacts', label: 'Contacts', icon: Users },
  { to: '/transactions', label: 'Transactions', icon: Receipt },
  { to: '/locations', label: 'Locations', icon: MapPin },
  { to: '/exhibitions', label: 'Exhibitions', icon: Calendar },
  { to: '/documents', label: 'Documents', icon: FileText },
  { to: '/settings', label: 'Settings', icon: Settings },
];

export function Sidebar() {
  return (
    <aside className="hidden md:flex w-64 flex-col border-r border-sidebar-border bg-sidebar">
      <div className="flex h-14 items-center border-b border-sidebar-border px-4">
        <span className="text-lg font-semibold text-sidebar-foreground">
          Art Inventory
        </span>
      </div>
      <nav className="flex-1 space-y-1 p-3">
        {navItems.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === '/'}
            className={({ isActive }) =>
              cn(
                'flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-sidebar-accent text-sidebar-accent-foreground'
                  : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground'
              )
            }
          >
            <item.icon className="h-4 w-4" />
            {item.label}
          </NavLink>
        ))}
      </nav>
    </aside>
  );
}
