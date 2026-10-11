import React, { useState } from 'react';
import { Organization } from '../types';
import { Building, Globe, Mail, Shield, Check, Save } from 'lucide-react';

interface Props {
  organization: Organization;
  onUpdateOrg: (org: Organization) => void;
}

export const OrgSettingsView: React.FC<Props> = ({ organization, onUpdateOrg }) => {
  const [name, setName] = useState(organization.name);
  const [website, setWebsite] = useState(organization.website);
  const [contactEmail, setContactEmail] = useState(organization.contactEmail);
  const [publicDirectoryEnabled, setPublicDirectoryEnabled] = useState(
    organization.publicDirectoryEnabled
  );
  const [saved, setSaved] = useState(false);

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    onUpdateOrg({
      ...organization,
      name,
      website,
      contactEmail,
      publicDirectoryEnabled,
    });
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
    <div className="max-w-3xl space-y-6">
      <div className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm">
        <h2 className="text-xl font-bold text-slate-900">Organization Settings</h2>
        <p className="text-sm text-slate-500 mt-1">
          Configure profile details, company directory visibility, and primary branding.
        </p>
      </div>

      <form onSubmit={handleSave} className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm space-y-6">
        <div>
          <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
            Organization Name
          </label>
          <input
            type="text"
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
          />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
              Official Website
            </label>
            <input
              type="url"
              value={website}
              onChange={(e) => setWebsite(e.target.value)}
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 uppercase tracking-wider mb-1.5">
              Contact Email
            </label>
            <input
              type="email"
              value={contactEmail}
              onChange={(e) => setContactEmail(e.target.value)}
              className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
            />
          </div>
        </div>

        {/* Directory Visibility Switch */}
        <div className="p-4 rounded-2xl border border-slate-200 bg-slate-50/50 flex items-center justify-between gap-4">
          <div>
            <h4 className="text-sm font-bold text-slate-900">Public Company Directory</h4>
            <p className="text-xs text-slate-500 mt-0.5">
              When enabled, a public page listing all public team cards is published at /directory/{organization.slug}.
            </p>
          </div>
          <label className="relative inline-flex items-center cursor-pointer">
            <input
              type="checkbox"
              checked={publicDirectoryEnabled}
              onChange={(e) => setPublicDirectoryEnabled(e.target.checked)}
              className="sr-only peer"
            />
            <div className="w-11 h-6 bg-slate-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-5 after:width-5 after:transition-all peer-checked:bg-indigo-600"></div>
          </label>
        </div>

        <div className="pt-2 flex items-center justify-end">
          <button
            type="submit"
            className="flex items-center gap-2 px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-semibold text-sm shadow-md shadow-indigo-600/20 transition-all"
          >
            {saved ? <Check className="w-4 h-4 text-emerald-300" /> : <Save className="w-4 h-4" />}
            {saved ? 'Changes Saved!' : 'Save Settings'}
          </button>
        </div>
      </form>
    </div>
  );
};
