import React, { useState } from 'react';
import { DigitalCard } from '../types';
import {
  Plus,
  Search,
  Filter,
  QrCode,
  Share2,
  Edit,
  Eye,
  Download,
  MoreVertical,
  Trash2,
  Copy,
  ExternalLink,
  ShieldCheck,
  CheckCircle,
  XCircle,
  Sparkles,
} from 'lucide-react';
import { downloadVCard } from '../utils/vcard';
import { CardQRCodeModal } from './CardQRCodeModal';

interface Props {
  cards: DigitalCard[];
  onOpenEditor: (card?: DigitalCard) => void;
  onPreviewCard: (slug: string) => void;
  onDeleteCard: (id: string) => void;
  onDuplicateCard: (card: DigitalCard) => void;
  onToggleStatus: (id: string) => void;
  seatsUsed: number;
  seatsLimit: number;
}

export const CardsView: React.FC<Props> = ({
  cards,
  onOpenEditor,
  onPreviewCard,
  onDeleteCard,
  onDuplicateCard,
  onToggleStatus,
  seatsUsed,
  seatsLimit,
}) => {
  const [search, setSearch] = useState('');
  const [selectedStatus, setSelectedStatus] = useState<string>('all');
  const [activeQrCard, setActiveQrCard] = useState<DigitalCard | null>(null);

  const filteredCards = cards.filter((card) => {
    const matchesSearch =
      card.fullName.toLowerCase().includes(search.toLowerCase()) ||
      card.jobTitle.toLowerCase().includes(search.toLowerCase()) ||
      card.department.toLowerCase().includes(search.toLowerCase());

    const matchesStatus =
      selectedStatus === 'all' ||
      (selectedStatus === 'active' && card.status === 'active') ||
      (selectedStatus === 'disabled' && card.status === 'disabled') ||
      (selectedStatus === 'public' && card.visibility === 'public');

    return matchesSearch && matchesStatus;
  });

  const slotsAvailable = seatsLimit - seatsUsed;

  return (
    <div className="space-y-6">
      {/* Top Banner / Actions */}
      <div className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-slate-900">Digital Business Cards</h2>
          <p className="text-sm text-slate-500 mt-1">
            Manage your organization's digital identity cards, custom links, and visibility.
          </p>
          <div className="flex items-center gap-2 mt-2">
            <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-100">
              {seatsUsed} of {seatsLimit} Card Slots Used
            </span>
            {slotsAvailable > 0 ? (
              <span className="text-xs text-emerald-600 font-medium">
                ({slotsAvailable} slot{slotsAvailable === 1 ? '' : 's'} available)
              </span>
            ) : (
              <span className="text-xs text-amber-600 font-medium">
                (Card capacity reached - buy seats in Shop)
              </span>
            )}
          </div>
        </div>

        <button
          onClick={() => onOpenEditor()}
          disabled={slotsAvailable <= 0}
          className="flex items-center gap-2 px-5 py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed text-white font-semibold text-sm shadow-md shadow-indigo-600/20 transition-all active:scale-[0.98]"
        >
          <Plus className="w-4 h-4" />
          Create New Card
        </button>
      </div>

      {/* Filter Bar */}
      <div className="flex flex-col sm:flex-row items-center gap-3">
        <div className="relative flex-1 w-full">
          <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            placeholder="Search by member name, job title, department..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2.5 rounded-2xl border border-slate-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 shadow-sm"
          />
        </div>

        <div className="flex items-center gap-2 w-full sm:w-auto">
          <select
            value={selectedStatus}
            onChange={(e) => setSelectedStatus(e.target.value)}
            className="px-4 py-2.5 rounded-2xl border border-slate-200 bg-white text-sm font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 shadow-sm"
          >
            <option value="all">All Cards ({cards.length})</option>
            <option value="active">Active Only</option>
            <option value="disabled">Disabled Only</option>
            <option value="public">Public Directory Only</option>
          </select>
        </div>
      </div>

      {/* Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredCards.map((card) => {
          const isActive = card.status === 'active';
          return (
            <div
              key={card.id}
              className="bg-white rounded-3xl border border-slate-200/80 overflow-hidden shadow-sm hover:shadow-md transition-all flex flex-col group"
            >
              {/* Card Cover & Avatar */}
              <div className="relative h-28 bg-gradient-to-r from-indigo-500 to-violet-600 overflow-hidden">
                {card.coverUrl && (
                  <img
                    src={card.coverUrl}
                    alt="Cover"
                    className="w-full h-full object-cover opacity-80 group-hover:scale-105 transition-transform duration-500"
                  />
                )}
                <div className="absolute top-3 right-3 flex items-center gap-1.5">
                  <span
                    className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider backdrop-blur-md ${
                      isActive
                        ? 'bg-emerald-500/90 text-white'
                        : 'bg-slate-800/80 text-slate-200'
                    }`}
                  >
                    {card.status}
                  </span>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider bg-black/40 text-white backdrop-blur-md">
                    {card.visibility}
                  </span>
                </div>
              </div>

              {/* Card Header */}
              <div className="px-5 pt-0 pb-4 relative flex-1 flex flex-col">
                <div className="flex justify-between items-end -mt-9 mb-3">
                  <img
                    src={card.avatarUrl}
                    alt={card.fullName}
                    className="w-16 h-16 rounded-2xl object-cover border-4 border-white shadow-md bg-white"
                  />
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => setActiveQrCard(card)}
                      className="p-2 rounded-xl text-slate-500 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
                      title="Show QR Code"
                    >
                      <QrCode className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => onPreviewCard(card.slug)}
                      className="p-2 rounded-xl text-slate-500 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
                      title="Live Card Preview"
                    >
                      <Eye className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => onOpenEditor(card)}
                      className="p-2 rounded-xl text-slate-500 hover:text-indigo-600 hover:bg-indigo-50 transition-colors"
                      title="Edit Card"
                    >
                      <Edit className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div>
                  <h3 className="font-bold text-slate-900 text-base leading-snug">
                    {card.fullName}
                  </h3>
                  <p className="text-xs font-semibold text-indigo-600 mt-0.5">
                    {card.jobTitle}
                  </p>
                  <p className="text-xs text-slate-400 mt-0.5">
                    {card.department} &bull; {card.companyName}
                  </p>
                </div>

                <p className="text-xs text-slate-600 mt-3 line-clamp-2 leading-relaxed">
                  {card.bio || 'No bio provided.'}
                </p>

                {/* Stats row */}
                <div className="mt-4 pt-3 border-t border-slate-100 grid grid-cols-3 gap-2 text-center text-xs">
                  <div>
                    <span className="font-bold text-slate-900 block">{card.stats.views}</span>
                    <span className="text-[10px] text-slate-400 uppercase tracking-wider">Views</span>
                  </div>
                  <div>
                    <span className="font-bold text-slate-900 block">{card.stats.saves}</span>
                    <span className="text-[10px] text-slate-400 uppercase tracking-wider">Saves</span>
                  </div>
                  <div>
                    <span className="font-bold text-slate-900 block">{card.stats.qrScans}</span>
                    <span className="text-[10px] text-slate-400 uppercase tracking-wider">Scans</span>
                  </div>
                </div>

                {/* Actions Footer */}
                <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-xs font-medium text-slate-500">
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => downloadVCard(card)}
                      className="hover:text-indigo-600 flex items-center gap-1 text-[11px]"
                      title="Download vCard (.vcf)"
                    >
                      <Download className="w-3.5 h-3.5" />
                      vCard
                    </button>
                    <button
                      onClick={() => onDuplicateCard(card)}
                      className="hover:text-indigo-600 flex items-center gap-1 text-[11px]"
                      title="Duplicate Card"
                    >
                      <Copy className="w-3.5 h-3.5" />
                      Copy
                    </button>
                  </div>

                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => onToggleStatus(card.id)}
                      className={`text-[11px] font-semibold px-2 py-0.5 rounded-lg transition-colors ${
                        isActive
                          ? 'text-amber-700 bg-amber-50 hover:bg-amber-100'
                          : 'text-emerald-700 bg-emerald-50 hover:bg-emerald-100'
                      }`}
                    >
                      {isActive ? 'Disable' : 'Activate'}
                    </button>
                    <button
                      onClick={() => onDeleteCard(card.id)}
                      className="text-slate-400 hover:text-red-600 p-1 rounded-lg hover:bg-red-50 transition-colors"
                      title="Delete card"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>
              </div>
            </div>
          );
        })}

        {filteredCards.length === 0 && (
          <div className="col-span-full py-16 text-center bg-white rounded-3xl border border-slate-200">
            <Sparkles className="w-10 h-10 text-slate-300 mx-auto mb-3" />
            <h3 className="font-bold text-slate-800 text-lg">No cards found</h3>
            <p className="text-xs text-slate-400 mt-1">Try modifying your search or create a new card.</p>
          </div>
        )}
      </div>

      {activeQrCard && (
        <CardQRCodeModal
          card={activeQrCard}
          onClose={() => setActiveQrCard(null)}
          onPreview={(slug) => onPreviewCard(slug)}
        />
      )}
    </div>
  );
};
