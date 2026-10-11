import React, { useState } from 'react';
import {
  Sparkles,
  Layers,
  Cpu,
  Globe2,
  Share2,
  CheckCircle2,
  ShieldCheck,
  Send,
  Zap,
  PhoneCall,
  Clock,
  ArrowRight,
  X,
} from 'lucide-react';
import { Organization } from '../types';

interface ServiceItem {
  id: string;
  title: string;
  tagline: string;
  category: 'Enterprise' | 'Design' | 'Hardware' | 'Integration';
  priceDisplay: string;
  deliveryTime: string;
  description: string;
  highlights: string[];
  icon: any;
  featured?: boolean;
}

const BIZZVOT_SERVICES: ServiceItem[] = [
  {
    id: 'srv_white_label',
    title: 'Custom Domain & White-Labeling',
    tagline: 'Host cards at card.yourcompany.com with zero Bizzvot branding',
    category: 'Enterprise',
    priceDisplay: '$120 / year',
    deliveryTime: '24-hour DNS provisioning',
    description:
      'Seamlessly point your company domain or subdomain to Bizzvot. Complete white-labeling includes custom favicon, brand footer, custom SSL certificate, and OpenGraph social share branding.',
    highlights: [
      'Custom CNAME setup with automatic SSL renewal',
      'Removal of all "Powered by Bizzvot" badges',
      'Corporate email domain matching',
      'Dedicated technical onboarding specialist',
    ],
    icon: Globe2,
    featured: true,
  },
  {
    id: 'srv_nfc_batch',
    title: 'Bulk NFC Encoding & Precision Laser Engraving',
    tagline: 'Custom company logo engraved onto matte black or steel NFC cards',
    category: 'Hardware',
    priceDisplay: 'From $19 / unit (min 10)',
    deliveryTime: '3-5 business days delivery',
    description:
      'Ship pre-configured, pre-tested NFC smart cards directly to your distributed team members with your company logo laser-etched onto every card. Ready to tap out of the box.',
    highlights: [
      'High-precision fiber laser etching of vector logos',
      'Dual NFC chip write & lock for lifetime reliability',
      'Custom luxury gift packaging per employee',
      'Individual address worldwide fulfillment',
    ],
    icon: Cpu,
    featured: true,
  },
  {
    id: 'srv_crm_sync',
    title: 'CRM & Lead Capture Automation',
    tagline: 'Sync every card connection directly to Salesforce or HubSpot',
    category: 'Integration',
    priceDisplay: '$49 / month',
    deliveryTime: 'Instant webhook activation',
    description:
      'When someone saves your card or submits a review, automatically push their verified contact details, notes, and timestamp directly into your sales pipeline or CRM.',
    highlights: [
      'Native connectors for HubSpot, Salesforce & Zoho',
      'Webhooks for Zapier and Make.com workflows',
      'Automatic duplicate contact deduplication',
      'Enriched company firmographics lookup',
    ],
    icon: Share2,
  },
  {
    id: 'srv_custom_templates',
    title: 'Bespoke Executive Card Design',
    tagline: 'Custom CSS layout matched to your brand guidelines',
    category: 'Design',
    priceDisplay: '$250 one-time',
    deliveryTime: '2 business days',
    description:
      'Our senior UI/UX designers create a signature, branded layout for your leadership team adhering strictly to your corporate fonts, color tokens, and layout guidelines.',
    highlights: [
      'Pixel-perfect adherence to brand identity kits',
      'Custom interactive widgets (calendars, pricing, video reels)',
      'Handcrafted micro-animations and transition states',
      '3 revision rounds with lead art director',
    ],
    icon: Layers,
  },
  {
    id: 'srv_sso_directory',
    title: 'Okta & Azure AD Directory Sync',
    tagline: 'Auto-provision cards when new staff join your HR system',
    category: 'Enterprise',
    priceDisplay: '$390 / year',
    deliveryTime: 'Same-day SAML 2.0 setup',
    description:
      'Eliminate manual card creation. Automatically provision, update, or revoke employee digital cards based on Active Directory, Okta, or Google Workspace user groups.',
    highlights: [
      'SAML 2.0 / SCIM protocol provisioning',
      'Auto-generation of card slugs and QR codes',
      'Role-based permission synchronization',
      'SOC2 and GDPR compliance audit logs',
    ],
    icon: ShieldCheck,
  },
  {
    id: 'srv_vip_concierge',
    title: 'VIP Concierge Team Onboarding',
    tagline: 'Turnkey card rollout for entire sales and executive teams',
    category: 'Enterprise',
    priceDisplay: '$190 one-time',
    deliveryTime: '1-on-1 scheduled sessions',
    description:
      'A dedicated Bizzvot customer success manager uploads photos, formats biographies, tests NFC cards, and runs a live 30-minute training session for your staff.',
    highlights: [
      'Full data entry and profile photo enhancement',
      'Live interactive team workshop over Google Meet / Zoom',
      'Custom quick-start PDF guide for staff phones',
      '90-day priority concierge WhatsApp support',
    ],
    icon: Zap,
  },
];

interface Props {
  organization: Organization;
  onRequestService?: (serviceName: string) => void;
}

export const ServicesView: React.FC<Props> = ({ organization, onRequestService }) => {
  const [selectedService, setSelectedService] = useState<ServiceItem | null>(null);
  const [submitted, setSubmitted] = useState(false);
  const [contactName, setContactName] = useState('Sarah Jenkins');
  const [contactEmail, setContactEmail] = useState(organization.contactEmail || 'contact@apexinnovations.example.com');
  const [serviceNotes, setServiceNotes] = useState('');

  const handleSubmitRequest = (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedService) return;
    setSubmitted(true);
    onRequestService?.(selectedService.title);
    setTimeout(() => {
      setSubmitted(false);
      setSelectedService(null);
      setServiceNotes('');
    }, 2000);
  };

  return (
    <div className="space-y-8 pb-12">
      {/* Services Header */}
      <div className="bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 text-white p-6 sm:p-8 rounded-3xl shadow-lg border border-slate-800 relative overflow-hidden">
        <div className="relative z-10 max-w-2xl space-y-3">
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-indigo-500/20 text-indigo-300 text-xs font-bold border border-indigo-400/30">
            <Sparkles className="w-3.5 h-3.5 text-indigo-400" />
            Professional Organization Services
          </div>
          <h2 className="text-2xl sm:text-3xl font-extrabold tracking-tight">
            Bizzvot Enterprise & Professional Services
          </h2>
          <p className="text-sm text-slate-300 leading-relaxed">
            From custom domain white-labeling and bulk laser-engraved NFC hardware to Okta SCIM sync and bespoke card templates—empower your organization with turnkey digital identity solutions.
          </p>
        </div>
      </div>

      {/* Services Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {BIZZVOT_SERVICES.map((srv) => {
          const Icon = srv.icon;
          return (
            <div
              key={srv.id}
              className={`bg-white rounded-3xl p-6 border transition-all flex flex-col justify-between hover:shadow-lg ${
                srv.featured
                  ? 'border-indigo-200 shadow-md ring-1 ring-indigo-500/10'
                  : 'border-slate-200/80 shadow-sm'
              }`}
            >
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div className="w-12 h-12 rounded-2xl bg-indigo-50 text-indigo-600 flex items-center justify-center shadow-inner">
                    <Icon className="w-6 h-6" />
                  </div>
                  <span className="text-[11px] font-bold px-2.5 py-1 rounded-full bg-slate-100 text-slate-700">
                    {srv.category}
                  </span>
                </div>

                <h3 className="text-lg font-bold text-slate-900 leading-snug mb-1">
                  {srv.title}
                </h3>
                <p className="text-xs font-semibold text-indigo-600 mb-3">
                  {srv.tagline}
                </p>

                <div className="bg-slate-50 p-3 rounded-2xl border border-slate-100 mb-4 flex items-center justify-between text-xs">
                  <div>
                    <span className="font-extrabold text-slate-900 block text-sm">
                      {srv.priceDisplay}
                    </span>
                    <span className="text-[10px] text-slate-400">Pricing</span>
                  </div>
                  <div className="text-right">
                    <span className="font-medium text-slate-700 flex items-center gap-1 justify-end">
                      <Clock className="w-3 h-3 text-slate-400" />
                      {srv.deliveryTime}
                    </span>
                    <span className="text-[10px] text-slate-400">Turnaround</span>
                  </div>
                </div>

                <p className="text-xs text-slate-600 leading-relaxed mb-4">
                  {srv.description}
                </p>

                <div className="space-y-1.5 mb-6 text-xs text-slate-700">
                  {srv.highlights.map((h, idx) => (
                    <div key={idx} className="flex items-start gap-2">
                      <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500 flex-shrink-0 mt-0.5" />
                      <span>{h}</span>
                    </div>
                  ))}
                </div>
              </div>

              <button
                onClick={() => setSelectedService(srv)}
                className="w-full py-2.5 px-4 rounded-xl bg-slate-900 hover:bg-indigo-600 text-white font-semibold text-xs shadow-sm transition-colors flex items-center justify-center gap-1.5"
              >
                <span>Request Service</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </button>
            </div>
          );
        })}
      </div>

      {/* Service Request Modal */}
      {selectedService && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl max-w-lg w-full p-6 border border-slate-200 relative">
            <button
              onClick={() => setSelectedService(null)}
              className="absolute top-5 right-5 text-slate-400 hover:text-slate-600"
            >
              <X className="w-5 h-5" />
            </button>

            {submitted ? (
              <div className="text-center py-8 space-y-3">
                <CheckCircle2 className="w-14 h-14 text-emerald-500 mx-auto" />
                <h3 className="text-xl font-bold text-slate-900">Request Received!</h3>
                <p className="text-xs text-slate-500">
                  A Bizzvot specialist will reach out to <span className="font-semibold">{contactEmail}</span> to begin your {selectedService.title} setup.
                </p>
              </div>
            ) : (
              <form onSubmit={handleSubmitRequest} className="space-y-4">
                <div>
                  <span className="text-[11px] font-bold text-indigo-600 uppercase tracking-wider">
                    {selectedService.category} Service
                  </span>
                  <h3 className="text-xl font-bold text-slate-900 mt-0.5">
                    Request {selectedService.title}
                  </h3>
                  <p className="text-xs text-slate-500 mt-1">
                    {selectedService.tagline} &bull; {selectedService.priceDisplay}
                  </p>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Contact Name *
                  </label>
                  <input
                    type="text"
                    required
                    value={contactName}
                    onChange={(e) => setContactName(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Corporate Email *
                  </label>
                  <input
                    type="email"
                    required
                    value={contactEmail}
                    onChange={(e) => setContactEmail(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Specific Requirements or Team Size (Optional)
                  </label>
                  <textarea
                    rows={3}
                    value={serviceNotes}
                    onChange={(e) => setServiceNotes(e.target.value)}
                    placeholder="e.g. Need 25 laser-engraved steel cards with logo, or custom domain card.apexinnovations.com"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>

                <div className="bg-slate-50 p-3.5 rounded-xl border border-slate-200 text-xs text-slate-600 flex items-center gap-2">
                  <ShieldCheck className="w-4 h-4 text-emerald-600 flex-shrink-0" />
                  <span>No payment required now. Our engineering team prepares a tailored deployment plan.</span>
                </div>

                <button
                  type="submit"
                  className="w-full py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-md shadow-indigo-600/20 transition-all flex items-center justify-center gap-2"
                >
                  <Send className="w-4 h-4" />
                  Submit Service Request
                </button>
              </form>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
