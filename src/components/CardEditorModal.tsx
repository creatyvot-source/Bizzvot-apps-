import React, { useState } from 'react';
import { DigitalCard, CardTemplate, CardVisibility, CardStatus, CardLink } from '../types';
import { X, Plus, Trash2, Globe, Sparkles, Smartphone, Check } from 'lucide-react';

interface Props {
  card?: DigitalCard | null;
  isOpen: boolean;
  onClose: () => void;
  onSave: (card: DigitalCard) => void;
}

const TEMPLATES: { id: CardTemplate; name: string; desc: string }[] = [
  { id: 'cover_card', name: 'Cover Card', desc: 'Bold gradient header with stacked content' },
  { id: 'modern_dark', name: 'Modern Dark', desc: 'Sleek dark mode theme with neon accents' },
  { id: 'corporate', name: 'Corporate', desc: 'Clean, structured executive layout' },
  { id: 'profile_hub', name: 'Profile Hub', desc: 'Central avatar with rounded quick links' },
  { id: 'minimal', name: 'Minimal', desc: 'Essential contact info with typography focus' },
];

const ACCENT_COLORS = [
  '#4F46E5', // Indigo
  '#0EA5E9', // Sky
  '#10B981', // Emerald
  '#F59E0B', // Amber
  '#EC4899', // Pink
  '#8B5CF6', // Purple
  '#1E293B', // Slate
];

export const CardEditorModal: React.FC<Props> = ({ card, isOpen, onClose, onSave }) => {
  if (!isOpen) return null;

  const [fullName, setFullName] = useState(card?.fullName || '');
  const [jobTitle, setJobTitle] = useState(card?.jobTitle || '');
  const [department, setDepartment] = useState(card?.department || '');
  const [companyName, setCompanyName] = useState(card?.companyName || 'Apex Innovations Inc.');
  const [email, setEmail] = useState(card?.email || '');
  const [phone, setPhone] = useState(card?.phone || '');
  const [location, setLocation] = useState(card?.location || '');
  const [bio, setBio] = useState(card?.bio || '');
  const [avatarUrl, setAvatarUrl] = useState(
    card?.avatarUrl || 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400&auto=format&fit=crop&q=80'
  );
  const [coverUrl, setCoverUrl] = useState(
    card?.coverUrl || 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800&auto=format&fit=crop&q=80'
  );
  const [template, setTemplate] = useState<CardTemplate>(card?.template || 'cover_card');
  const [status, setStatus] = useState<CardStatus>(card?.status || 'active');
  const [visibility, setVisibility] = useState<CardVisibility>(card?.visibility || 'public');
  const [accentColor, setAccentColor] = useState(card?.accentColor || '#4F46E5');
  const [links, setLinks] = useState<CardLink[]>(
    card?.links || [
      { id: '1', type: 'linkedin', label: 'LinkedIn', url: 'https://linkedin.com' },
      { id: '2', type: 'website', label: 'Website', url: 'https://example.com' },
    ]
  );

  const [activeTab, setActiveTab] = useState<'details' | 'links' | 'appearance'>('details');

  const handleAddLink = () => {
    setLinks([
      ...links,
      {
        id: Date.now().toString(),
        type: 'custom',
        label: 'New Link',
        url: 'https://',
      },
    ]);
  };

  const handleUpdateLink = (id: string, updates: Partial<CardLink>) => {
    setLinks(links.map((link) => (link.id === id ? { ...link, ...updates } : link)));
  };

  const handleRemoveLink = (id: string) => {
    setLinks(links.filter((link) => link.id !== id));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const slug =
      card?.slug ||
      fullName
        .toLowerCase()
        .replace(/[^a-z0-9]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '') ||
      `card-${Date.now().toString().slice(-4)}`;

    const newCard: DigitalCard = {
      id: card?.id || `card_${Date.now()}`,
      slug,
      fullName,
      jobTitle,
      department,
      companyName,
      email,
      phone,
      location,
      bio,
      avatarUrl,
      coverUrl,
      template,
      status,
      visibility,
      accentColor,
      links,
      gallery: card?.gallery || [],
      documents: card?.documents || [],
      stats: card?.stats || { views: 0, saves: 0, qrScans: 0, shares: 0 },
      assignedStaffId: card?.assignedStaffId,
      createdAt: card?.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    onSave(newCard);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto animate-in fade-in duration-200">
      <div className="bg-white rounded-3xl shadow-2xl max-w-4xl w-full max-h-[90vh] flex flex-col overflow-hidden border border-slate-200 my-auto">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50">
          <div>
            <h2 className="text-xl font-bold text-slate-900">
              {card ? 'Edit Digital Card' : 'Create New Digital Card'}
            </h2>
            <p className="text-xs text-slate-500">Configure profile, contact details, links and visual appearance</p>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl text-slate-400 hover:text-slate-600 hover:bg-slate-200/60 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Tab switcher */}
        <div className="flex border-b border-slate-200 px-6 gap-6 bg-white">
          <button
            onClick={() => setActiveTab('details')}
            className={`py-3 text-sm font-semibold border-b-2 transition-all ${
              activeTab === 'details'
                ? 'border-indigo-600 text-indigo-600'
                : 'border-transparent text-slate-500 hover:text-slate-800'
            }`}
          >
            Personal & Contact
          </button>
          <button
            onClick={() => setActiveTab('appearance')}
            className={`py-3 text-sm font-semibold border-b-2 transition-all ${
              activeTab === 'appearance'
                ? 'border-indigo-600 text-indigo-600'
                : 'border-transparent text-slate-500 hover:text-slate-800'
            }`}
          >
            Design & Templates
          </button>
          <button
            onClick={() => setActiveTab('links')}
            className={`py-3 text-sm font-semibold border-b-2 transition-all ${
              activeTab === 'links'
                ? 'border-indigo-600 text-indigo-600'
                : 'border-transparent text-slate-500 hover:text-slate-800'
            }`}
          >
            Social & Action Links ({links.length})
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto p-6 space-y-6">
          {activeTab === 'details' && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Full Name *
                  </label>
                  <input
                    type="text"
                    required
                    value={fullName}
                    onChange={(e) => setFullName(e.target.value)}
                    placeholder="e.g. Sarah Jenkins"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Job Title *
                  </label>
                  <input
                    type="text"
                    required
                    value={jobTitle}
                    onChange={(e) => setJobTitle(e.target.value)}
                    placeholder="e.g. Chief Executive Officer"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Company Name
                  </label>
                  <input
                    type="text"
                    value={companyName}
                    onChange={(e) => setCompanyName(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Department
                  </label>
                  <input
                    type="text"
                    value={department}
                    onChange={(e) => setDepartment(e.target.value)}
                    placeholder="e.g. Engineering, Sales"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Email Address *
                  </label>
                  <input
                    type="email"
                    required
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    placeholder="name@company.com"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Phone Number
                  </label>
                  <input
                    type="tel"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="+1 (555) 000-0000"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Location
                  </label>
                  <input
                    type="text"
                    value={location}
                    onChange={(e) => setLocation(e.target.value)}
                    placeholder="e.g. San Francisco, CA"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                  Professional Bio
                </label>
                <textarea
                  rows={3}
                  value={bio}
                  onChange={(e) => setBio(e.target.value)}
                  placeholder="Short introductory bio about your experience, focus areas, and role..."
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Avatar Image URL
                  </label>
                  <input
                    type="url"
                    value={avatarUrl}
                    onChange={(e) => setAvatarUrl(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Cover Banner Image URL
                  </label>
                  <input
                    type="url"
                    value={coverUrl}
                    onChange={(e) => setCoverUrl(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 pt-2">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Card Status
                  </label>
                  <select
                    value={status}
                    onChange={(e) => setStatus(e.target.value as CardStatus)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm bg-white"
                  >
                    <option value="active">Active (Available)</option>
                    <option value="disabled">Disabled (Hidden from public)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1">
                    Directory Visibility
                  </label>
                  <select
                    value={visibility}
                    onChange={(e) => setVisibility(e.target.value as CardVisibility)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-indigo-600/20 focus:border-indigo-600 text-sm bg-white"
                  >
                    <option value="public">Public (Visible in directory & search)</option>
                    <option value="inherit">Inherit (Follow organization rule)</option>
                    <option value="private">Private (Link / QR only)</option>
                  </select>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'appearance' && (
            <div className="space-y-6">
              <div>
                <label className="block text-sm font-semibold text-slate-800 mb-3">
                  Select Card Template
                </label>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {TEMPLATES.map((tmpl) => (
                    <div
                      key={tmpl.id}
                      onClick={() => setTemplate(tmpl.id)}
                      className={`p-4 rounded-2xl border cursor-pointer transition-all ${
                        template === tmpl.id
                          ? 'border-indigo-600 bg-indigo-50/50 shadow-sm ring-2 ring-indigo-600/20'
                          : 'border-slate-200 hover:border-slate-300 hover:bg-slate-50'
                      }`}
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="font-semibold text-slate-900 text-sm">{tmpl.name}</span>
                        {template === tmpl.id && <Check className="w-4 h-4 text-indigo-600" />}
                      </div>
                      <p className="text-xs text-slate-500">{tmpl.desc}</p>
                    </div>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-sm font-semibold text-slate-800 mb-3">
                  Accent Color
                </label>
                <div className="flex flex-wrap items-center gap-3">
                  {ACCENT_COLORS.map((color) => (
                    <button
                      type="button"
                      key={color}
                      onClick={() => setAccentColor(color)}
                      style={{ backgroundColor: color }}
                      className={`w-10 h-10 rounded-full border-2 transition-transform ${
                        accentColor === color ? 'scale-110 border-white ring-2 ring-indigo-600 shadow-md' : 'border-transparent'
                      }`}
                    />
                  ))}
                  <div className="flex items-center gap-2 ml-2">
                    <span className="text-xs text-slate-500">Custom:</span>
                    <input
                      type="color"
                      value={accentColor}
                      onChange={(e) => setAccentColor(e.target.value)}
                      className="w-8 h-8 rounded-lg cursor-pointer border border-slate-200 p-0.5"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {activeTab === 'links' && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <p className="text-xs text-slate-500">Add social accounts, scheduling links, websites or portfolio URLs</p>
                <button
                  type="button"
                  onClick={handleAddLink}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-indigo-50 text-indigo-600 font-semibold text-xs hover:bg-indigo-100 transition-colors"
                >
                  <Plus className="w-3.5 h-3.5" />
                  Add Link
                </button>
              </div>

              <div className="space-y-3">
                {links.map((link) => (
                  <div key={link.id} className="p-3.5 rounded-xl border border-slate-200 bg-slate-50 flex flex-col sm:flex-row gap-3 items-center">
                    <select
                      value={link.type}
                      onChange={(e) => handleUpdateLink(link.id, { type: e.target.value as any })}
                      className="w-full sm:w-36 px-3 py-2 rounded-lg border border-slate-200 bg-white text-xs font-medium"
                    >
                      <option value="linkedin">LinkedIn</option>
                      <option value="x">X / Twitter</option>
                      <option value="github">GitHub</option>
                      <option value="website">Website</option>
                      <option value="calendly">Calendly</option>
                      <option value="whatsapp">WhatsApp</option>
                      <option value="instagram">Instagram</option>
                      <option value="youtube">YouTube</option>
                      <option value="custom">Custom Link</option>
                    </select>

                    <input
                      type="text"
                      placeholder="Button Label"
                      value={link.label}
                      onChange={(e) => handleUpdateLink(link.id, { label: e.target.value })}
                      className="w-full sm:w-44 px-3 py-2 rounded-lg border border-slate-200 bg-white text-xs"
                    />

                    <input
                      type="url"
                      placeholder="Destination URL (https://...)"
                      value={link.url}
                      onChange={(e) => handleUpdateLink(link.id, { url: e.target.value })}
                      className="flex-1 w-full px-3 py-2 rounded-lg border border-slate-200 bg-white text-xs"
                    />

                    <button
                      type="button"
                      onClick={() => handleRemoveLink(link.id)}
                      className="p-2 text-slate-400 hover:text-red-500 rounded-lg hover:bg-red-50 transition-colors"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                ))}

                {links.length === 0 && (
                  <div className="text-center py-8 border-2 border-dashed border-slate-200 rounded-2xl">
                    <Globe className="w-8 h-8 text-slate-300 mx-auto mb-2" />
                    <p className="text-sm font-medium text-slate-600">No links added yet</p>
                    <p className="text-xs text-slate-400 mt-1">Add your social channels or meeting links</p>
                  </div>
                )}
              </div>
            </div>
          )}

          <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              className="px-5 py-2.5 rounded-xl border border-slate-200 text-slate-600 font-semibold text-sm hover:bg-slate-50 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-semibold text-sm shadow-md shadow-indigo-600/20 transition-all flex items-center gap-2"
            >
              <Check className="w-4 h-4" />
              Save Card
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
