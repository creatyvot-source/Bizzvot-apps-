import React, { useState } from 'react';
import { DigitalCard } from '../types';
import { X, Copy, Check, Download, ExternalLink } from 'lucide-react';

interface Props {
  card: DigitalCard;
  onClose: () => void;
  onPreview: (slug: string) => void;
}

export const CardQRCodeModal: React.FC<Props> = ({ card, onClose, onPreview }) => {
  const [copied, setCopied] = useState(false);
  const cardUrl = `${window.location.origin}/card/${card.slug}`;
  const qrImageUrl = `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${encodeURIComponent(cardUrl)}&color=4f46e5`;

  const handleCopy = () => {
    navigator.clipboard.writeText(cardUrl);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownloadQr = () => {
    const a = document.createElement('a');
    a.href = qrImageUrl;
    a.download = `${card.slug}-qr-code.png`;
    a.target = '_blank';
    a.click();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
      <div className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden border border-slate-100">
        <div className="bg-gradient-to-r from-indigo-600 to-violet-600 px-6 py-5 text-white flex items-center justify-between">
          <div className="flex items-center space-x-3">
            <img
              src={card.avatarUrl}
              alt={card.fullName}
              className="w-10 h-10 rounded-full object-cover border-2 border-white/50 shadow-sm"
            />
            <div>
              <h3 className="font-semibold text-lg leading-tight">{card.fullName}</h3>
              <p className="text-xs text-indigo-100">{card.jobTitle}</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-white/80 hover:text-white p-1 rounded-lg hover:bg-white/10 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="p-6 text-center">
          <div className="bg-slate-50 p-6 rounded-2xl inline-block border border-slate-200/80 shadow-inner mb-4">
            <img
              src={qrImageUrl}
              alt={`QR Code for ${card.fullName}`}
              className="w-52 h-52 mx-auto rounded-lg shadow-sm"
            />
          </div>

          <p className="text-sm font-medium text-slate-700 mb-1">
            Scan to instantly view & save digital contact card
          </p>
          <p className="text-xs text-slate-500 mb-6 break-all px-4 font-mono">
            {cardUrl}
          </p>

          <div className="grid grid-cols-2 gap-3 mb-4">
            <button
              onClick={handleCopy}
              className="flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl border border-slate-200 text-slate-700 hover:bg-slate-50 font-medium text-sm transition-all"
            >
              {copied ? <Check className="w-4 h-4 text-emerald-600" /> : <Copy className="w-4 h-4 text-slate-500" />}
              {copied ? 'Link Copied' : 'Copy Link'}
            </button>
            <button
              onClick={handleDownloadQr}
              className="flex items-center justify-center gap-2 py-2.5 px-4 rounded-xl border border-slate-200 text-slate-700 hover:bg-slate-50 font-medium text-sm transition-all"
            >
              <Download className="w-4 h-4 text-slate-500" />
              Save PNG
            </button>
          </div>

          <button
            onClick={() => {
              onClose();
              onPreview(card.slug);
            }}
            className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-semibold text-sm shadow-md shadow-indigo-600/20 transition-all"
          >
            <ExternalLink className="w-4 h-4" />
            Open Card Profile
          </button>
        </div>
      </div>
    </div>
  );
};
