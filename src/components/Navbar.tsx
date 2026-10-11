import React, { useState } from 'react';
import { UserRole, Organization, CartItem } from '../types';
import {
  CreditCard,
  LayoutDashboard,
  ShoppingBag,
  Globe,
  Sparkles,
  Users,
  Star,
  Settings,
  Bell,
  UserCheck,
  ChevronDown,
} from 'lucide-react';
import { Persona, AVAILABLE_PERSONAS } from './FloatingMenu';

interface Props {
  activeTab: string;
  onTabChange: (tab: string) => void;
  organization: Organization;
  cart: CartItem[];
  currentPersona: Persona;
  onSelectPersona: (persona: Persona) => void;
  onOpenShop: () => void;
}

export const Navbar: React.FC<Props> = ({
  activeTab,
  onTabChange,
  organization,
  cart,
  currentPersona,
  onSelectPersona,
  onOpenShop,
}) => {
  const [showNotifications, setShowNotifications] = useState(false);
  const [showPersonaMenu, setShowPersonaMenu] = useState(false);
  const cartCount = cart.reduce((acc, item) => acc + item.quantity, 0);

  const notifications = [
    { id: '1', title: 'New 5-star review received', text: 'Marcus Vance reviewed Sarah Jenkins', time: '10m ago' },
    { id: '2', title: 'NFC Cards Dispatched', text: 'Tracking #BV-9042 is on its way', time: '1h ago' },
    { id: '3', title: 'Seat capacity alert', text: '5 of 6 card slots currently assigned', time: 'Yesterday' },
  ];

  const primaryTabs = [
    { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { id: 'cards', label: 'Cards', icon: CreditCard },
    { id: 'shop', label: 'Shop', icon: ShoppingBag },
    { id: 'directory', label: 'Directory', icon: Globe },
    { id: 'services', label: 'Services', icon: Sparkles },
  ];

  return (
    <header className="sticky top-0 z-40 bg-white/95 backdrop-blur-md border-b border-slate-200">
      {/* Top Banner with Multi-Login Quick Switcher & Organization status */}
      <div className="bg-slate-900 text-white px-4 py-2 text-xs flex flex-col sm:flex-row items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
          <span className="font-semibold text-slate-300">
            Multi-Login Active:
          </span>

          {/* Quick Persona Dropdown */}
          <div className="relative">
            <button
              onClick={() => setShowPersonaMenu(!showPersonaMenu)}
              className="flex items-center gap-2 px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-white font-medium border border-slate-700 transition-colors"
            >
              <img
                src={currentPersona.avatarUrl}
                alt={currentPersona.name}
                className="w-4 h-4 rounded-full object-cover"
              />
              <span>{currentPersona.name}</span>
              <span className="text-[10px] uppercase font-bold text-indigo-300 bg-indigo-950/80 px-1 rounded">
                {currentPersona.tag}
              </span>
              <ChevronDown className="w-3 h-3 text-slate-400" />
            </button>

            {showPersonaMenu && (
              <div className="absolute left-0 mt-1 w-64 bg-slate-900 text-white rounded-2xl shadow-2xl border border-slate-700 p-2 z-50 animate-in fade-in duration-150">
                <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400 px-2 py-1">
                  1-Click Multi-Login (No Password)
                </p>
                <div className="space-y-1 mt-1">
                  {AVAILABLE_PERSONAS.map((p) => (
                    <button
                      key={p.id}
                      onClick={() => {
                        onSelectPersona(p);
                        setShowPersonaMenu(false);
                      }}
                      className={`w-full flex items-center gap-2.5 px-2.5 py-2 rounded-xl text-left text-xs transition-colors ${
                        currentPersona.id === p.id
                          ? 'bg-indigo-600 text-white font-bold'
                          : 'hover:bg-slate-800 text-slate-200'
                      }`}
                    >
                      <img
                        src={p.avatarUrl}
                        alt={p.name}
                        className="w-6 h-6 rounded-full object-cover"
                      />
                      <div className="min-w-0 flex-1">
                        <p className="font-semibold truncate">{p.name}</p>
                        <p className="text-[10px] text-slate-400 truncate">{p.roleTitle}</p>
                      </div>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="flex items-center gap-3 text-slate-300">
          <span className="text-slate-400 font-medium">
            {organization.name}
          </span>
          <span className="text-slate-600">&bull;</span>
          <span className="text-emerald-400 text-[11px] font-semibold">
            {organization.plan}
          </span>
        </div>
      </div>

      {/* Main Navigation Bar */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
        {/* Brand */}
        <div className="flex items-center gap-8">
          <div
            onClick={() => onTabChange('dashboard')}
            className="flex items-center gap-2.5 cursor-pointer"
          >
            <div className="w-9 h-9 rounded-xl bg-indigo-600 text-white flex items-center justify-center font-black text-lg shadow-md shadow-indigo-600/30">
              B
            </div>
            <div>
              <span className="font-extrabold text-lg tracking-tight text-slate-900">
                Bizzvot
              </span>
              <span className="text-[10px] font-bold uppercase tracking-wider text-indigo-600 block -mt-1">
                Apps
              </span>
            </div>
          </div>

          {/* Primary 5 Tabs: Dashboard, Cards, Shop, Directory, Services */}
          <nav className="hidden md:flex items-center gap-1 text-sm font-medium">
            {primaryTabs.map((item) => {
              const Icon = item.icon;
              const active = activeTab === item.id;
              return (
                <button
                  key={item.id}
                  onClick={() => onTabChange(item.id)}
                  className={`flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs font-bold transition-all ${
                    active
                      ? 'bg-indigo-50 text-indigo-600'
                      : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100/60'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  {item.label}
                </button>
              );
            })}
          </nav>
        </div>

        {/* Right Nav Actions */}
        <div className="flex items-center gap-2.5">
          {/* Notifications */}
          <div className="relative">
            <button
              onClick={() => setShowNotifications(!showNotifications)}
              className="p-2.5 rounded-xl text-slate-500 hover:text-slate-800 hover:bg-slate-100 relative transition-colors"
            >
              <Bell className="w-4 h-4" />
              <span className="absolute top-2 right-2 w-2 h-2 rounded-full bg-indigo-600" />
            </button>

            {showNotifications && (
              <div className="absolute right-0 mt-2 w-80 bg-white rounded-2xl shadow-xl border border-slate-100 p-4 z-50 animate-in fade-in duration-150">
                <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400 mb-2">
                  Notifications
                </h4>
                <div className="space-y-2">
                  {notifications.map((n) => (
                    <div key={n.id} className="p-2.5 rounded-xl bg-slate-50 border border-slate-100 text-xs">
                      <p className="font-bold text-slate-800">{n.title}</p>
                      <p className="text-slate-500 text-[11px] mt-0.5">{n.text}</p>
                      <span className="text-[10px] text-slate-400 mt-1 block">{n.time}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Cart button */}
          <button
            onClick={onOpenShop}
            className="flex items-center gap-2 px-3.5 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-800 font-bold text-xs transition-colors"
          >
            <ShoppingBag className="w-4 h-4 text-indigo-600" />
            <span className="hidden sm:inline">Shop</span>
            {cartCount > 0 && (
              <span className="w-4 h-4 rounded-full bg-indigo-600 text-white text-[10px] flex items-center justify-center">
                {cartCount}
              </span>
            )}
          </button>
        </div>
      </div>
    </header>
  );
};
