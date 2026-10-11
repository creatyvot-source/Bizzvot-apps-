import React from 'react';
import { Organization, DigitalCard } from '../types';
import { ArrowLeft, ExternalLink, Sparkles, ShieldCheck } from 'lucide-react';

interface Props {
  organization: Organization;
  cards: DigitalCard[];
  onSelectCard: (slug: string) => void;
  onBackToApp: () => void;
}

export const PublicDirectoryView: React.FC<Props> = ({
  organization,
  cards,
  onSelectCard,
  onBackToApp,
}) => {
  const publicCards = cards.filter(
    (c) => c.status === 'active' && (c.visibility === 'public' || (c.visibility === 'inherit' && organization.publicDirectoryEnabled))
  );

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900 py-8 px-4">
      <div className="max-w-4xl mx-auto space-y-8">
        <div className="flex items-center justify-between">
          <button
            onClick={onBackToApp}
            className="flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-xl bg-white text-slate-700 hover:bg-slate-100 shadow-sm border border-slate-200 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            Back to App
          </button>
          <span className="text-xs text-slate-400 font-medium">Public Company Directory</span>
        </div>

        {/* Directory Header */}
        <div className="text-center py-6">
          <div className="w-16 h-16 rounded-3xl bg-indigo-600 text-white font-extrabold flex items-center justify-center text-2xl mx-auto mb-4 shadow-lg shadow-indigo-600/30">
            {organization.name.charAt(0)}
          </div>
          <h1 className="text-3xl font-extrabold text-slate-900">{organization.name}</h1>
          <p className="text-sm text-slate-500 mt-2 max-w-md mx-auto">
            Official team directory. Connect directly with our leadership, engineering, and partner executives.
          </p>
        </div>

        {/* Cards Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {publicCards.map((card) => (
            <div
              key={card.id}
              onClick={() => onSelectCard(card.slug)}
              className="bg-white rounded-3xl border border-slate-200/80 p-5 shadow-sm hover:shadow-md hover:border-indigo-300 transition-all cursor-pointer group flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center gap-3.5 mb-3">
                  <img
                    src={card.avatarUrl}
                    alt={card.fullName}
                    className="w-14 h-14 rounded-2xl object-cover border border-slate-200"
                  />
                  <div>
                    <h3 className="font-bold text-slate-900 text-sm group-hover:text-indigo-600 transition-colors">
                      {card.fullName}
                    </h3>
                    <p className="text-xs text-indigo-600 font-semibold">{card.jobTitle}</p>
                    <p className="text-[11px] text-slate-400">{card.department}</p>
                  </div>
                </div>

                <p className="text-xs text-slate-600 line-clamp-2 leading-relaxed">
                  {card.bio}
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-xs text-indigo-600 font-semibold">
                <span>View Card & Contact</span>
                <ExternalLink className="w-3.5 h-3.5 group-hover:translate-x-0.5 transition-transform" />
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
