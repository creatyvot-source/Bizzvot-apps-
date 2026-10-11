import React, { useState } from 'react';
import { StaffMember, DigitalCard } from '../types';
import {
  Users,
  Plus,
  Search,
  Check,
  Shield,
  CreditCard,
  Mail,
  Trash2,
  X,
  Lock,
} from 'lucide-react';

interface Props {
  staff: StaffMember[];
  cards: DigitalCard[];
  onAddStaff: (newStaff: StaffMember) => void;
  onRemoveStaff: (id: string) => void;
  onUpdatePermissions: (
    id: string,
    perms: { canEditCard: boolean; canViewReviews: boolean; canViewAnalytics: boolean }
  ) => void;
  totalSeats: number;
}

export const TeamStaffView: React.FC<Props> = ({
  staff,
  cards,
  onAddStaff,
  onRemoveStaff,
  onUpdatePermissions,
  totalSeats,
}) => {
  const [search, setSearch] = useState('');
  const [isInviteOpen, setIsInviteOpen] = useState(false);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState('Account Executive');
  const [department, setDepartment] = useState('Sales');
  const [selectedCardId, setSelectedCardId] = useState<string>('');
  const [canEditCard, setCanEditCard] = useState(true);
  const [canViewReviews, setCanViewReviews] = useState(true);
  const [canViewAnalytics, setCanViewAnalytics] = useState(false);

  const cardMap = new Map(cards.map((c) => [c.id, c]));

  const filteredStaff = staff.filter(
    (m) =>
      m.name.toLowerCase().includes(search.toLowerCase()) ||
      m.email.toLowerCase().includes(search.toLowerCase()) ||
      m.role.toLowerCase().includes(search.toLowerCase()) ||
      m.department.toLowerCase().includes(search.toLowerCase())
  );

  const handleInvite = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !email.trim()) return;

    const newMember: StaffMember = {
      id: `staff_${Date.now()}`,
      name,
      email,
      role,
      department,
      cardId: selectedCardId || undefined,
      status: 'active',
      canEditCard,
      canViewReviews,
      canViewAnalytics,
      joinedDate: 'Oct 2026',
    };

    onAddStaff(newMember);
    setIsInviteOpen(false);
    setName('');
    setEmail('');
  };

  return (
    <div className="space-y-6">
      <div className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-slate-900">Team & Staff Governance</h2>
          <p className="text-sm text-slate-500 mt-1">
            Manage organization members, assigned digital cards, and administrative privileges.
          </p>
          <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-indigo-50 text-indigo-700 mt-2 inline-block border border-indigo-100">
            {staff.length} Active Members &bull; {totalSeats} Total Card Licenses
          </span>
        </div>

        <button
          onClick={() => setIsInviteOpen(true)}
          className="flex items-center gap-2 px-5 py-2.5 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-semibold text-xs shadow-md shadow-indigo-600/20 transition-all active:scale-[0.98]"
        >
          <Plus className="w-4 h-4" />
          Invite Team Member
        </button>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
        <input
          type="text"
          placeholder="Search team members by name, email, department or title..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="w-full pl-10 pr-4 py-2.5 rounded-2xl border border-slate-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 shadow-sm"
        />
      </div>

      {/* Staff Roster */}
      <div className="bg-white rounded-3xl border border-slate-200/80 overflow-hidden shadow-sm divide-y divide-slate-100">
        {filteredStaff.map((member) => {
          const card = member.cardId ? cardMap.get(member.cardId) : null;

          return (
            <div
              key={member.id}
              className="p-6 flex flex-col md:flex-row items-start md:items-center justify-between gap-6 hover:bg-slate-50/50 transition-colors"
            >
              <div className="flex items-start gap-4">
                <div className="w-12 h-12 rounded-2xl bg-indigo-100 text-indigo-700 font-bold flex items-center justify-center text-base border border-indigo-200 shadow-inner flex-shrink-0">
                  {member.name.charAt(0)}
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className="font-bold text-slate-900 text-sm">{member.name}</h4>
                    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700">
                      {member.status.toUpperCase()}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 mt-0.5">
                    {member.role} &bull; {member.department}
                  </p>
                  <p className="text-xs text-slate-400 mt-0.5 flex items-center gap-1 font-mono">
                    <Mail className="w-3.5 h-3.5" />
                    {member.email}
                  </p>

                  {card && (
                    <div className="mt-2 flex items-center gap-1.5 text-xs text-indigo-600 font-medium">
                      <CreditCard className="w-3.5 h-3.5" />
                      <span>Assigned Card: /card/{card.slug}</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Permissions checkboxes */}
              <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 text-xs">
                <div className="flex items-center gap-3 bg-slate-50 p-2.5 rounded-2xl border border-slate-200/80">
                  <label className="flex items-center gap-1.5 cursor-pointer text-slate-700 font-medium">
                    <input
                      type="checkbox"
                      checked={member.canEditCard}
                      onChange={(e) =>
                        onUpdatePermissions(member.id, {
                          canEditCard: e.target.checked,
                          canViewReviews: member.canViewReviews,
                          canViewAnalytics: member.canViewAnalytics,
                        })
                      }
                      className="rounded text-indigo-600 focus:ring-indigo-600"
                    />
                    Edit Card
                  </label>

                  <label className="flex items-center gap-1.5 cursor-pointer text-slate-700 font-medium">
                    <input
                      type="checkbox"
                      checked={member.canViewReviews}
                      onChange={(e) =>
                        onUpdatePermissions(member.id, {
                          canEditCard: member.canEditCard,
                          canViewReviews: e.target.checked,
                          canViewAnalytics: member.canViewAnalytics,
                        })
                      }
                      className="rounded text-indigo-600 focus:ring-indigo-600"
                    />
                    Reviews
                  </label>

                  <label className="flex items-center gap-1.5 cursor-pointer text-slate-700 font-medium">
                    <input
                      type="checkbox"
                      checked={member.canViewAnalytics}
                      onChange={(e) =>
                        onUpdatePermissions(member.id, {
                          canEditCard: member.canEditCard,
                          canViewReviews: member.canViewReviews,
                          canViewAnalytics: e.target.checked,
                        })
                      }
                      className="rounded text-indigo-600 focus:ring-indigo-600"
                    />
                    Analytics
                  </label>
                </div>

                <button
                  onClick={() => onRemoveStaff(member.id)}
                  className="p-2 text-slate-400 hover:text-red-600 hover:bg-red-50 rounded-xl transition-colors"
                  title="Remove Member"
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            </div>
          );
        })}

        {filteredStaff.length === 0 && (
          <div className="p-12 text-center text-slate-400 text-sm">
            No team members matched your search.
          </div>
        )}
      </div>

      {/* Invite Member Modal */}
      {isInviteOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl max-w-md w-full p-6 border border-slate-200 relative">
            <button
              onClick={() => setIsInviteOpen(false)}
              className="absolute top-5 right-5 text-slate-400 hover:text-slate-600"
            >
              <X className="w-5 h-5" />
            </button>

            <h3 className="text-xl font-bold text-slate-900 mb-1">Invite Team Member</h3>
            <p className="text-xs text-slate-500 mb-5">
              Add a staff member to your organization and grant card editor access.
            </p>

            <form onSubmit={handleInvite} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Full Name *
                </label>
                <input
                  type="text"
                  required
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. Jordan Smith"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Work Email *
                </label>
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="jordan@company.com"
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Role / Title
                  </label>
                  <input
                    type="text"
                    value={role}
                    onChange={(e) => setRole(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-slate-700 mb-1">
                    Department
                  </label>
                  <input
                    type="text"
                    value={department}
                    onChange={(e) => setDepartment(e.target.value)}
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Assign to Digital Card
                </label>
                <select
                  value={selectedCardId}
                  onChange={(e) => setSelectedCardId(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600 bg-white"
                >
                  <option value="">None (Assign later)</option>
                  {cards.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.fullName} - {c.jobTitle}
                    </option>
                  ))}
                </select>
              </div>

              <button
                type="submit"
                className="w-full py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-md shadow-indigo-600/20 transition-all flex items-center justify-center gap-2 mt-4"
              >
                <Users className="w-4 h-4" />
                Send Invitation
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
