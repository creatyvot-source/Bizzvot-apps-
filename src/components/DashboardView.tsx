import React from 'react';
import { DigitalCard, Organization, StaffMember, CardReview } from '../types';
import {
  CreditCard,
  Users,
  Eye,
  Star,
  Plus,
  ArrowUpRight,
  ShieldCheck,
  AlertTriangle,
  QrCode,
  ExternalLink,
  ShoppingBag,
  Sparkles,
  ChevronRight,
  TrendingUp,
} from 'lucide-react';

interface Props {
  organization: Organization;
  cards: DigitalCard[];
  staff: StaffMember[];
  reviews: CardReview[];
  onNavigate: (tab: string) => void;
  onOpenCardEditor: () => void;
  onPreviewCard: (slug: string) => void;
}

export const DashboardView: React.FC<Props> = ({
  organization,
  cards,
  staff,
  reviews,
  onNavigate,
  onOpenCardEditor,
  onPreviewCard,
}) => {
  const totalViews = cards.reduce((acc, c) => acc + c.stats.views, 0);
  const totalSaves = cards.reduce((acc, c) => acc + c.stats.saves, 0);
  const totalScans = cards.reduce((acc, c) => acc + c.stats.qrScans, 0);
  const activeCards = cards.filter((c) => c.status === 'active');
  const cardSlotsFull = cards.length >= organization.totalCardSlots;

  const averageRating =
    reviews.length > 0
      ? (reviews.reduce((acc, r) => acc + r.rating, 0) / reviews.length).toFixed(1)
      : '5.0';

  return (
    <div className="space-y-8">
      {/* Hero Welcome / Organization Banner */}
      <div className="relative rounded-3xl overflow-hidden bg-gradient-to-r from-indigo-700 via-indigo-600 to-violet-700 text-white p-6 sm:p-8 shadow-xl shadow-indigo-700/10">
        <div className="relative z-10 flex flex-col md:flex-row items-start md:items-center justify-between gap-6">
          <div className="space-y-2">
            <div className="inline-flex items-center gap-2 bg-white/15 backdrop-blur-md px-3 py-1 rounded-full text-xs font-semibold tracking-wide border border-white/20">
              <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
              {organization.plan} &bull; {organization.planStatus.toUpperCase()}
            </div>
            <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight">
              {organization.name}
            </h1>
            <p className="text-sm text-indigo-100 max-w-xl">
              Centralized command center for team digital cards, verified client reviews, NFC smart cards, and public organization directory.
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-3">
            <button
              onClick={() => onNavigate('shop')}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-white/10 hover:bg-white/20 text-white font-semibold text-xs backdrop-blur-md border border-white/20 transition-all"
            >
              <ShoppingBag className="w-4 h-4" />
              NFC Shop & Add-ons
            </button>
            <button
              onClick={onOpenCardEditor}
              disabled={cardSlotsFull}
              className="flex items-center gap-2 px-5 py-2.5 rounded-xl bg-white text-indigo-700 hover:bg-indigo-50 font-bold text-xs shadow-md transition-all active:scale-[0.98]"
            >
              <Plus className="w-4 h-4" />
              New Card
            </button>
          </div>
        </div>

        {/* Subtle decorative circles */}
        <div className="absolute -right-10 -bottom-10 w-64 h-64 rounded-full bg-white/5 pointer-events-none blur-2xl" />
      </div>

      {/* Trial / Capacity Warning Alert if near capacity */}
      {cardSlotsFull && (
        <div className="p-4 rounded-2xl bg-amber-50 border border-amber-200/80 flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <AlertTriangle className="w-5 h-5 text-amber-600 flex-shrink-0" />
            <div>
              <p className="text-sm font-bold text-amber-900">All Card Slots In Use</p>
              <p className="text-xs text-amber-700">
                You have allocated all {organization.totalCardSlots} slots. Expand seats in the Shop to add more team members.
              </p>
            </div>
          </div>
          <button
            onClick={() => onNavigate('shop')}
            className="px-4 py-2 rounded-xl bg-amber-600 hover:bg-amber-700 text-white font-semibold text-xs shadow-sm flex-shrink-0 transition-colors"
          >
            Add Seats
          </button>
        </div>
      )}

      {/* Metrics Row */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider block mb-1">
              Active Cards
            </span>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-slate-900">{activeCards.length}</span>
              <span className="text-xs font-medium text-slate-400">/ {organization.totalCardSlots} slots</span>
            </div>
            <div className="w-28 bg-slate-100 h-1.5 rounded-full mt-2.5 overflow-hidden">
              <div
                className="bg-indigo-600 h-full rounded-full transition-all"
                style={{ width: `${Math.min(100, (cards.length / organization.totalCardSlots) * 100)}%` }}
              />
            </div>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-indigo-50 flex items-center justify-center text-indigo-600">
            <CreditCard className="w-6 h-6" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider block mb-1">
              Total Impressions
            </span>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-slate-900">{totalViews.toLocaleString()}</span>
              <span className="text-xs font-medium text-emerald-600 flex items-center">
                <TrendingUp className="w-3 h-3 mr-0.5" /> +18%
              </span>
            </div>
            <span className="text-[11px] text-slate-400 mt-1 block">Views across all links & QRs</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-sky-50 flex items-center justify-center text-sky-600">
            <Eye className="w-6 h-6" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider block mb-1">
              Contact Saves
            </span>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-slate-900">{totalSaves.toLocaleString()}</span>
              <span className="text-xs font-medium text-slate-400">({totalScans} QR scans)</span>
            </div>
            <span className="text-[11px] text-slate-400 mt-1 block">Downloaded to address book</span>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-emerald-50 flex items-center justify-center text-emerald-600">
            <QrCode className="w-6 h-6" />
          </div>
        </div>

        <div className="bg-white p-5 rounded-2xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div>
            <span className="text-xs font-semibold text-slate-400 uppercase tracking-wider block mb-1">
              Client Reputation
            </span>
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-extrabold text-slate-900 flex items-center gap-1">
                {averageRating}
                <Star className="w-5 h-5 fill-amber-400 text-amber-400" />
              </span>
              <span className="text-xs font-medium text-slate-400">({reviews.length} reviews)</span>
            </div>
            <button
              onClick={() => onNavigate('reviews')}
              className="text-[11px] text-indigo-600 font-semibold hover:underline mt-1 block"
            >
              View feedback &rarr;
            </button>
          </div>
          <div className="w-12 h-12 rounded-2xl bg-amber-50 flex items-center justify-center text-amber-600">
            <Star className="w-6 h-6 fill-amber-500" />
          </div>
        </div>
      </div>

      {/* Cards Table / Preview Quick-Access */}
      <div className="bg-white rounded-3xl border border-slate-200/80 overflow-hidden shadow-sm">
        <div className="p-6 border-b border-slate-100 flex items-center justify-between">
          <div>
            <h3 className="font-bold text-slate-900 text-lg">Team Digital Cards</h3>
            <p className="text-xs text-slate-500">Live preview of your organization's digital cards</p>
          </div>
          <button
            onClick={() => onNavigate('cards')}
            className="text-xs font-bold text-indigo-600 hover:text-indigo-800 flex items-center gap-1"
          >
            Manage All Cards ({cards.length}) <ChevronRight className="w-4 h-4" />
          </button>
        </div>

        <div className="divide-y divide-slate-100">
          {cards.slice(0, 4).map((card) => (
            <div
              key={card.id}
              className="p-5 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 hover:bg-slate-50/80 transition-colors"
            >
              <div className="flex items-center gap-4">
                <img
                  src={card.avatarUrl}
                  alt={card.fullName}
                  className="w-12 h-12 rounded-2xl object-cover border border-slate-200 shadow-sm"
                />
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className="font-bold text-slate-900 text-sm">{card.fullName}</h4>
                    <span
                      className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase ${
                        card.status === 'active'
                          ? 'bg-emerald-50 text-emerald-700'
                          : 'bg-slate-100 text-slate-600'
                      }`}
                    >
                      {card.status}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500">{card.jobTitle} &bull; {card.department}</p>
                  <p className="text-[11px] text-slate-400 font-mono mt-0.5">/card/{card.slug}</p>
                </div>
              </div>

              <div className="flex items-center gap-4 w-full sm:w-auto justify-between sm:justify-end">
                <div className="text-right text-xs">
                  <span className="font-bold text-slate-900 block">{card.stats.views} views</span>
                  <span className="text-[11px] text-slate-400">{card.stats.saves} contacts saved</span>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => onPreviewCard(card.slug)}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-slate-200 bg-white hover:bg-slate-50 text-slate-700 font-semibold text-xs shadow-sm transition-all"
                  >
                    <ExternalLink className="w-3.5 h-3.5" />
                    Preview
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Quick Links / Hardware promo */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="bg-gradient-to-br from-slate-900 to-slate-800 text-white p-6 rounded-3xl shadow-md flex items-center justify-between">
          <div className="space-y-2">
            <span className="text-[10px] uppercase tracking-wider font-bold text-indigo-400 bg-indigo-950/60 px-2.5 py-1 rounded-full border border-indigo-800/50">
              Hardware Integration
            </span>
            <h4 className="text-lg font-bold">Matte Black NFC Cards</h4>
            <p className="text-xs text-slate-300 max-w-sm">
              Tap against any smartphone to instantly exchange your profile without requiring any app install.
            </p>
            <button
              onClick={() => onNavigate('shop')}
              className="mt-2 inline-flex items-center gap-1.5 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-500 px-4 py-2 rounded-xl transition-colors"
            >
              Order Cards in Shop &rarr;
            </button>
          </div>
          <div className="hidden sm:block">
            <ShoppingBag className="w-16 h-16 text-indigo-400/40" />
          </div>
        </div>

        <div className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm flex items-center justify-between">
          <div className="space-y-2">
            <span className="text-[10px] uppercase tracking-wider font-bold text-emerald-600 bg-emerald-50 px-2.5 py-1 rounded-full border border-emerald-100">
              Reputation Engine
            </span>
            <h4 className="text-lg font-bold text-slate-900">Client Reviews</h4>
            <p className="text-xs text-slate-500 max-w-sm">
              Collect verified feedback directly on your digital card. Moderate testimonials and publish replies.
            </p>
            <button
              onClick={() => onNavigate('reviews')}
              className="mt-2 inline-flex items-center gap-1.5 text-xs font-bold text-indigo-600 hover:text-indigo-800"
            >
              Manage Reviews ({reviews.length}) &rarr;
            </button>
          </div>
          <div className="hidden sm:block">
            <Star className="w-16 h-16 text-amber-400/30 fill-amber-400/30" />
          </div>
        </div>
      </div>
    </div>
  );
};
