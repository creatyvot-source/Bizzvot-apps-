import React, { useState } from 'react';
import {
  LayoutDashboard,
  CreditCard,
  ShoppingBag,
  Globe,
  Sparkles,
  Users2,
  Check,
  ChevronUp,
  X,
  UserCheck,
  Shield,
  Eye,
} from 'lucide-react';
import { UserRole, CartItem } from '../types';

export interface Persona {
  id: string;
  name: string;
  roleTitle: string;
  roleType: UserRole;
  avatarUrl: string;
  tag: string;
  description: string;
  assignedCardSlug?: string;
}

export const AVAILABLE_PERSONAS: Persona[] = [
  {
    id: 'persona_sarah',
    name: 'Sarah Jenkins',
    roleTitle: 'Founder & Chief Executive',
    roleType: 'owner',
    avatarUrl:
      'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150&auto=format&fit=crop&q=80',
    tag: 'Organization Owner',
    description: 'Full administrative access to Dashboard, Cards, Shop, Team, and Reviews',
    assignedCardSlug: 'sarah-jenkins',
  },
  {
    id: 'persona_david',
    name: 'David Chen',
    roleTitle: 'Principal Solutions Architect',
    roleType: 'staff',
    avatarUrl:
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&auto=format&fit=crop&q=80',
    tag: 'Staff Member',
    description: 'Staff portal view with assigned card editor, architecture docs, and reviews',
    assignedCardSlug: 'david-chen',
  },
  {
    id: 'persona_maya',
    name: 'Maya Patel',
    roleTitle: 'Head of Partnerships',
    roleType: 'staff',
    avatarUrl:
      'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=150&auto=format&fit=crop&q=80',
    tag: 'Staff Member',
    description: 'Staff partnership card with WhatsApp quick chat and deck downloads',
    assignedCardSlug: 'maya-patel',
  },
  {
    id: 'persona_alex',
    name: 'Alex Rivera',
    roleTitle: 'Senior Product Designer',
    roleType: 'staff',
    avatarUrl:
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&auto=format&fit=crop&q=80',
    tag: 'Staff Member',
    description: 'Designer card with portfolio highlights, Behance, and Instagram link',
    assignedCardSlug: 'alex-rivera',
  },
  {
    id: 'persona_public',
    name: 'Public Visitor',
    roleTitle: 'Client / Prospect (No Login)',
    roleType: 'public',
    avatarUrl:
      'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150&auto=format&fit=crop&q=80',
    tag: 'Anonymous Client',
    description: 'Experience cards as an external client, save vCards, or scan QR codes',
    assignedCardSlug: 'sarah-jenkins',
  },
];

interface Props {
  activeTab: string;
  onSelectTab: (tab: string) => void;
  currentRole: UserRole;
  currentPersona: Persona;
  onSelectPersona: (persona: Persona) => void;
  cart: CartItem[];
}

export const FloatingMenu: React.FC<Props> = ({
  activeTab,
  onSelectTab,
  currentRole,
  currentPersona,
  onSelectPersona,
  cart,
}) => {
  const [isPersonaDrawerOpen, setIsPersonaDrawerOpen] = useState(false);
  const cartItemCount = cart.reduce((acc, i) => acc + i.quantity, 0);

  const navItems = [
    { id: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { id: 'cards', label: 'Cards', icon: CreditCard },
    { id: 'shop', label: 'Shop', icon: ShoppingBag, badge: cartItemCount > 0 ? cartItemCount : undefined },
    { id: 'directory', label: 'Directory', icon: Globe },
    { id: 'services', label: 'Services', icon: Sparkles },
  ];

  return (
    <>
      {/* Floating Dock Fixed at Bottom Center */}
      <div className="fixed bottom-5 left-1/2 -translate-x-1/2 z-50 max-w-full px-3">
        <div className="flex items-center gap-1.5 p-1.5 bg-slate-900/90 text-white backdrop-blur-xl border border-white/15 shadow-2xl rounded-full transition-all">
          {/* Main 5 Primary Buttons */}
          <div className="flex items-center gap-1">
            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = activeTab === item.id;

              return (
                <button
                  key={item.id}
                  onClick={() => onSelectTab(item.id)}
                  className={`relative flex items-center gap-1.5 px-3.5 py-2 rounded-full text-xs font-semibold transition-all ${
                    isActive
                      ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/30'
                      : 'text-slate-300 hover:text-white hover:bg-white/10'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  <span className="hidden sm:inline">{item.label}</span>
                  {item.badge !== undefined && (
                    <span className="w-4 h-4 rounded-full bg-amber-400 text-slate-950 font-black text-[10px] flex items-center justify-center -ml-0.5">
                      {item.badge}
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Divider */}
          <div className="w-[1px] h-6 bg-white/20 mx-1" />

          {/* Multi-Login Quick Switcher Trigger */}
          <button
            onClick={() => setIsPersonaDrawerOpen(!isPersonaDrawerOpen)}
            className="flex items-center gap-2 pl-1 pr-3 py-1 rounded-full bg-white/10 hover:bg-white/20 text-white text-xs font-semibold transition-all border border-white/15"
            title="Multi-Login: Switch profile without password"
          >
            <img
              src={currentPersona.avatarUrl}
              alt={currentPersona.name}
              className="w-6 h-6 rounded-full object-cover border border-white/40"
            />
            <span className="hidden md:inline max-w-[90px] truncate">
              {currentPersona.name.split(' ')[0]}
            </span>
            <span className="text-[10px] uppercase font-bold text-indigo-300 bg-indigo-950/80 px-1.5 py-0.5 rounded-full border border-indigo-700/60 hidden lg:inline">
              {currentPersona.roleType}
            </span>
            <ChevronUp
              className={`w-3.5 h-3.5 text-slate-400 transition-transform ${
                isPersonaDrawerOpen ? 'rotate-180' : ''
              }`}
            />
          </button>
        </div>
      </div>

      {/* Multi-Login Persona Switcher Modal Drawer */}
      {isPersonaDrawerOpen && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl max-w-md w-full overflow-hidden border border-slate-200 mb-16 sm:mb-0">
            {/* Header */}
            <div className="bg-gradient-to-r from-slate-900 to-indigo-950 text-white p-5 flex items-center justify-between">
              <div>
                <div className="flex items-center gap-2">
                  <UserCheck className="w-5 h-5 text-indigo-400" />
                  <h3 className="font-bold text-base">Multi-Login All-In-One Hub</h3>
                </div>
                <p className="text-xs text-slate-300 mt-0.5">
                  Instant 1-click persona switching (no passwords needed)
                </p>
              </div>
              <button
                onClick={() => setIsPersonaDrawerOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-white hover:bg-white/10"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Persona List */}
            <div className="p-4 space-y-2.5 max-h-[60vh] overflow-y-auto">
              {AVAILABLE_PERSONAS.map((persona) => {
                const isCurrent = currentPersona.id === persona.id;

                return (
                  <div
                    key={persona.id}
                    onClick={() => {
                      onSelectPersona(persona);
                      setIsPersonaDrawerOpen(false);
                    }}
                    className={`p-3.5 rounded-2xl border transition-all cursor-pointer flex items-center justify-between ${
                      isCurrent
                        ? 'bg-indigo-50/80 border-indigo-300 shadow-sm ring-1 ring-indigo-500/20'
                        : 'bg-white border-slate-200 hover:border-slate-300 hover:bg-slate-50'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <img
                        src={persona.avatarUrl}
                        alt={persona.name}
                        className="w-11 h-11 rounded-2xl object-cover border border-slate-200 shadow-sm"
                      />
                      <div>
                        <div className="flex items-center gap-2">
                          <h4 className="font-bold text-slate-900 text-sm">{persona.name}</h4>
                          <span
                            className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider ${
                              persona.roleType === 'owner'
                                ? 'bg-indigo-100 text-indigo-700'
                                : persona.roleType === 'staff'
                                ? 'bg-emerald-100 text-emerald-700'
                                : 'bg-slate-100 text-slate-700'
                            }`}
                          >
                            {persona.tag}
                          </span>
                        </div>
                        <p className="text-xs font-semibold text-slate-600 mt-0.5">
                          {persona.roleTitle}
                        </p>
                        <p className="text-[11px] text-slate-400 mt-0.5 line-clamp-1">
                          {persona.description}
                        </p>
                      </div>
                    </div>

                    {isCurrent && (
                      <div className="w-7 h-7 rounded-full bg-indigo-600 text-white flex items-center justify-center flex-shrink-0 shadow-sm">
                        <Check className="w-4 h-4" />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            <div className="px-5 py-3 bg-slate-50 border-t border-slate-100 text-center">
              <p className="text-[11px] text-slate-400">
                Switching personas updates permissions and views immediately without re-authenticating.
              </p>
            </div>
          </div>
        </div>
      )}
    </>
  );
};
