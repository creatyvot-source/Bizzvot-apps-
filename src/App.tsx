import React, { useState, useEffect } from 'react';
import {
  UserRole,
  DigitalCard,
  Organization,
  StaffMember,
  CardReview,
  ProductItem,
  CartItem,
  OrderRecord,
} from './types';
import {
  initialOrganization,
  initialCards,
  initialStaff,
  initialReviews,
  initialProducts,
  initialOrders,
} from './data/mockData';
import { Navbar } from './components/Navbar';
import { DashboardView } from './components/DashboardView';
import { CardsView } from './components/CardsView';
import { CardEditorModal } from './components/CardEditorModal';
import { PublicCardView } from './components/PublicCardView';
import { TeamStaffView } from './components/TeamStaffView';
import { ReviewsView } from './components/ReviewsView';
import { ShopView } from './components/ShopView';
import { ServicesView } from './components/ServicesView';
import { OrgSettingsView } from './components/OrgSettingsView';
import { PublicDirectoryView } from './components/PublicDirectoryView';
import { FloatingMenu, Persona, AVAILABLE_PERSONAS } from './components/FloatingMenu';

export function App() {
  // Current active persona for multi-login (default: Sarah Jenkins - Owner)
  const [currentPersona, setCurrentPersona] = useState<Persona>(() => {
    const savedId = localStorage.getItem('bizzvot_persona_id');
    const match = AVAILABLE_PERSONAS.find((p) => p.id === savedId);
    return match || AVAILABLE_PERSONAS[0];
  });

  // Current primary view tab: 'dashboard' | 'cards' | 'shop' | 'directory' | 'services'
  const [activeTab, setActiveTab] = useState<string>(() => {
    return localStorage.getItem('bizzvot_tab') || 'dashboard';
  });

  const [organization, setOrganization] = useState<Organization>(() => {
    const saved = localStorage.getItem('bizzvot_org');
    return saved ? JSON.parse(saved) : initialOrganization;
  });

  const [cards, setCards] = useState<DigitalCard[]>(() => {
    const saved = localStorage.getItem('bizzvot_cards');
    return saved ? JSON.parse(saved) : initialCards;
  });

  const [staff, setStaff] = useState<StaffMember[]>(() => {
    const saved = localStorage.getItem('bizzvot_staff');
    return saved ? JSON.parse(saved) : initialStaff;
  });

  const [reviews, setReviews] = useState<CardReview[]>(() => {
    const saved = localStorage.getItem('bizzvot_reviews');
    return saved ? JSON.parse(saved) : initialReviews;
  });

  const [cart, setCart] = useState<CartItem[]>(() => {
    const saved = localStorage.getItem('bizzvot_cart');
    return saved ? JSON.parse(saved) : [];
  });

  const [orders, setOrders] = useState<OrderRecord[]>(() => {
    const saved = localStorage.getItem('bizzvot_orders');
    return saved ? JSON.parse(saved) : initialOrders;
  });

  // Modal & Preview States
  const [editorCard, setEditorCard] = useState<DigitalCard | null | undefined>(undefined);
  const [isEditorOpen, setIsEditorOpen] = useState(false);
  const [previewingSlug, setPreviewingSlug] = useState<string | null>(null);

  // Sync to localStorage
  useEffect(() => {
    localStorage.setItem('bizzvot_persona_id', currentPersona.id);
  }, [currentPersona]);

  useEffect(() => {
    localStorage.setItem('bizzvot_tab', activeTab);
  }, [activeTab]);

  useEffect(() => {
    localStorage.setItem('bizzvot_org', JSON.stringify(organization));
  }, [organization]);

  useEffect(() => {
    localStorage.setItem('bizzvot_cards', JSON.stringify(cards));
  }, [cards]);

  useEffect(() => {
    localStorage.setItem('bizzvot_staff', JSON.stringify(staff));
  }, [staff]);

  useEffect(() => {
    localStorage.setItem('bizzvot_reviews', JSON.stringify(reviews));
  }, [reviews]);

  useEffect(() => {
    localStorage.setItem('bizzvot_cart', JSON.stringify(cart));
  }, [cart]);

  useEffect(() => {
    localStorage.setItem('bizzvot_orders', JSON.stringify(orders));
  }, [orders]);

  // Card Operations
  const handleSaveCard = (savedCard: DigitalCard) => {
    const exists = cards.some((c) => c.id === savedCard.id);
    if (exists) {
      setCards(cards.map((c) => (c.id === savedCard.id ? savedCard : c)));
    } else {
      setCards([...cards, savedCard]);
    }
  };

  const handleDeleteCard = (id: string) => {
    if (confirm('Are you sure you want to delete this digital card?')) {
      setCards(cards.filter((c) => c.id !== id));
    }
  };

  const handleDuplicateCard = (card: DigitalCard) => {
    const duplicate: DigitalCard = {
      ...card,
      id: `card_${Date.now()}`,
      slug: `${card.slug}-copy`,
      fullName: `${card.fullName} (Copy)`,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      stats: { views: 0, saves: 0, qrScans: 0, shares: 0 },
    };
    setCards([...cards, duplicate]);
  };

  const handleToggleCardStatus = (id: string) => {
    setCards(
      cards.map((c) =>
        c.id === id ? { ...c, status: c.status === 'active' ? 'disabled' : 'active' } : c
      )
    );
  };

  // Staff Operations
  const handleAddStaff = (newStaff: StaffMember) => {
    setStaff([...staff, newStaff]);
  };

  const handleRemoveStaff = (id: string) => {
    setStaff(staff.filter((s) => s.id !== id));
  };

  const handleUpdateStaffPermissions = (
    id: string,
    perms: { canEditCard: boolean; canViewReviews: boolean; canViewAnalytics: boolean }
  ) => {
    setStaff(
      staff.map((s) =>
        s.id === id
          ? {
              ...s,
              ...perms,
            }
          : s
      )
    );
  };

  // Review Operations
  const handleAddReview = (newReviewData: Omit<CardReview, 'id' | 'date' | 'status'>) => {
    const newRev: CardReview = {
      id: `rev_${Date.now()}`,
      date: new Date().toISOString(),
      status: 'approved',
      ...newReviewData,
    };
    setReviews([newRev, ...reviews]);
  };

  const handleToggleReviewStatus = (id: string) => {
    setReviews(
      reviews.map((r) =>
        r.id === id ? { ...r, status: r.status === 'approved' ? 'hidden' : 'approved' } : r
      )
    );
  };

  const handleReplyToReview = (id: string, reply: string) => {
    setReviews(
      reviews.map((r) => (r.id === id ? { ...r, ownerReply: reply } : r))
    );
  };

  // Cart & Orders Operations
  const handleAddToCart = (product: ProductItem) => {
    const existing = cart.find((i) => i.product.id === product.id);
    if (existing) {
      setCart(
        cart.map((i) =>
          i.product.id === product.id ? { ...i, quantity: i.quantity + 1 } : i
        )
      );
    } else {
      setCart([...cart, { product, quantity: 1 }]);
    }
  };

  const handleUpdateCartQty = (productId: string, qty: number) => {
    if (qty <= 0) {
      handleRemoveFromCart(productId);
      return;
    }
    setCart(
      cart.map((i) => (i.product.id === productId ? { ...i, quantity: qty } : i))
    );
  };

  const handleRemoveFromCart = (productId: string) => {
    setCart(cart.filter((i) => i.product.id !== productId));
  };

  const handleCheckout = (order: OrderRecord) => {
    setOrders([order, ...orders]);
    setCart([]);
  };

  // Click / Impression tracking
  const handleTrackAction = (cardId: string, actionType: string) => {
    setCards((prev) =>
      prev.map((c) => {
        if (c.id !== cardId) return c;
        const currentStats = { ...c.stats };
        if (actionType === 'share') currentStats.shares += 1;
        if (actionType === 'save') currentStats.saves += 1;
        if (actionType === 'qr') currentStats.qrScans += 1;
        if (actionType === 'view') currentStats.views += 1;
        return { ...c, stats: currentStats };
      })
    );
  };

  // If currently previewing a single public card
  if (previewingSlug) {
    const card = cards.find((c) => c.slug === previewingSlug) || cards[0];
    return (
      <div className="relative pb-24">
        <PublicCardView
          card={card}
          reviews={reviews}
          onBack={() => setPreviewingSlug(null)}
          onAddReview={handleAddReview}
          onTrackAction={handleTrackAction}
        />
        <FloatingMenu
          activeTab={activeTab}
          onSelectTab={(tab) => {
            setPreviewingSlug(null);
            setActiveTab(tab);
          }}
          currentRole={currentPersona.roleType}
          currentPersona={currentPersona}
          onSelectPersona={setCurrentPersona}
          cart={cart}
        />
      </div>
    );
  }

  // If in Public Visitor persona, direct to public experience
  if (currentPersona.roleType === 'public') {
    const publicCard = cards.find((c) => c.visibility === 'public') || cards[0];
    return (
      <div className="min-h-screen bg-slate-100 pb-28">
        <div className="bg-slate-900 text-white px-4 py-2 text-xs flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span className="font-semibold text-slate-300">Public Visitor Simulation:</span>
            <span className="text-slate-400">Browsing Apex Innovations Digital Cards</span>
          </div>
          <button
            onClick={() => setActiveTab('directory')}
            className="text-xs text-indigo-400 hover:text-white font-semibold underline"
          >
            All Team Cards Directory
          </button>
        </div>

        {activeTab === 'directory' ? (
          <PublicDirectoryView
            organization={organization}
            cards={cards}
            onSelectCard={(slug) => setPreviewingSlug(slug)}
            onBackToApp={() => setActiveTab('dashboard')}
          />
        ) : activeTab === 'shop' ? (
          <div className="max-w-7xl mx-auto px-4 py-8">
            <ShopView
              products={initialProducts}
              cart={cart}
              orders={orders}
              organization={organization}
              onAddToCart={handleAddToCart}
              onUpdateCartQty={handleUpdateCartQty}
              onRemoveFromCart={handleRemoveFromCart}
              onCheckout={handleCheckout}
            />
          </div>
        ) : activeTab === 'services' ? (
          <div className="max-w-7xl mx-auto px-4 py-8">
            <ServicesView
              organization={organization}
              onRequestService={(srv) => alert(`Request received for ${srv}!`)}
            />
          </div>
        ) : (
          <PublicCardView
            card={publicCard}
            reviews={reviews}
            onAddReview={handleAddReview}
            onTrackAction={handleTrackAction}
          />
        )}

        <FloatingMenu
          activeTab={activeTab}
          onSelectTab={setActiveTab}
          currentRole={currentPersona.roleType}
          currentPersona={currentPersona}
          onSelectPersona={setCurrentPersona}
          cart={cart}
        />
      </div>
    );
  }

  // If in Staff persona (e.g. David Chen, Maya Patel, Alex Rivera)
  if (currentPersona.roleType === 'staff') {
    const staffCard =
      cards.find((c) => c.slug === currentPersona.assignedCardSlug) ||
      cards.find((c) => c.slug === 'david-chen') ||
      cards[0];

    return (
      <div className="min-h-screen bg-[#F8F9FC] flex flex-col pb-28">
        <Navbar
          activeTab={activeTab}
          onTabChange={setActiveTab}
          organization={organization}
          cart={cart}
          currentPersona={currentPersona}
          onSelectPersona={setCurrentPersona}
          onOpenShop={() => setActiveTab('shop')}
        />

        <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {activeTab === 'dashboard' && (
            <div className="max-w-4xl mx-auto space-y-6">
              <div className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                <div className="flex items-center gap-4">
                  <img
                    src={currentPersona.avatarUrl}
                    alt={currentPersona.name}
                    className="w-16 h-16 rounded-2xl object-cover border border-slate-200 shadow-md"
                  />
                  <div>
                    <span className="text-[11px] font-bold uppercase tracking-wider text-indigo-600 bg-indigo-50 px-2.5 py-0.5 rounded-full">
                      Staff Portal
                    </span>
                    <h2 className="text-xl font-bold text-slate-900 mt-1">
                      Welcome, {currentPersona.name}
                    </h2>
                    <p className="text-xs text-slate-500 mt-0.5">
                      {currentPersona.roleTitle} &bull; {organization.name}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => setPreviewingSlug(staffCard.slug)}
                    className="px-4 py-2.5 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-800 text-xs font-semibold"
                  >
                    Preview Live Card
                  </button>
                  <button
                    onClick={() => {
                      setEditorCard(staffCard);
                      setIsEditorOpen(true);
                    }}
                    className="px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white text-xs font-bold shadow-md shadow-indigo-600/20"
                  >
                    Edit My Card
                  </button>
                </div>
              </div>

              {/* Staff's Card View */}
              <div className="bg-white rounded-3xl border border-slate-200/80 overflow-hidden shadow-sm p-6">
                <h3 className="font-bold text-slate-900 text-base mb-4">My Assigned Profile Card</h3>
                <div className="max-w-md mx-auto">
                  <PublicCardView
                    card={staffCard}
                    reviews={reviews}
                    onAddReview={handleAddReview}
                    onTrackAction={handleTrackAction}
                    isStandalone
                  />
                </div>
              </div>
            </div>
          )}

          {activeTab === 'cards' && (
            <CardsView
              cards={cards}
              seatsUsed={cards.length}
              seatsLimit={organization.totalCardSlots}
              onOpenEditor={(card) => {
                setEditorCard(card || null);
                setIsEditorOpen(true);
              }}
              onPreviewCard={(slug) => setPreviewingSlug(slug)}
              onDeleteCard={handleDeleteCard}
              onDuplicateCard={handleDuplicateCard}
              onToggleStatus={handleToggleCardStatus}
            />
          )}

          {activeTab === 'shop' && (
            <ShopView
              products={initialProducts}
              cart={cart}
              orders={orders}
              organization={organization}
              onAddToCart={handleAddToCart}
              onUpdateCartQty={handleUpdateCartQty}
              onRemoveFromCart={handleRemoveFromCart}
              onCheckout={handleCheckout}
            />
          )}

          {activeTab === 'directory' && (
            <PublicDirectoryView
              organization={organization}
              cards={cards}
              onSelectCard={(slug) => setPreviewingSlug(slug)}
              onBackToApp={() => setActiveTab('dashboard')}
            />
          )}

          {activeTab === 'services' && (
            <ServicesView
              organization={organization}
              onRequestService={(srv) => alert(`Request received for ${srv}!`)}
            />
          )}
        </main>

        <CardEditorModal
          isOpen={isEditorOpen}
          card={editorCard}
          onClose={() => setIsEditorOpen(false)}
          onSave={handleSaveCard}
        />

        <FloatingMenu
          activeTab={activeTab}
          onSelectTab={setActiveTab}
          currentRole={currentPersona.roleType}
          currentPersona={currentPersona}
          onSelectPersona={setCurrentPersona}
          cart={cart}
        />
      </div>
    );
  }

  // Owner Persona Experience (Default)
  return (
    <div className="min-h-screen bg-[#F8F9FC] flex flex-col pb-28">
      <Navbar
        activeTab={activeTab}
        onTabChange={setActiveTab}
        organization={organization}
        cart={cart}
        currentPersona={currentPersona}
        onSelectPersona={setCurrentPersona}
        onOpenShop={() => setActiveTab('shop')}
      />

      <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {activeTab === 'dashboard' && (
          <DashboardView
            organization={organization}
            cards={cards}
            staff={staff}
            reviews={reviews}
            onNavigate={setActiveTab}
            onOpenCardEditor={() => {
              setEditorCard(null);
              setIsEditorOpen(true);
            }}
            onPreviewCard={(slug) => setPreviewingSlug(slug)}
          />
        )}

        {activeTab === 'cards' && (
          <CardsView
            cards={cards}
            seatsUsed={cards.length}
            seatsLimit={organization.totalCardSlots}
            onOpenEditor={(card) => {
              setEditorCard(card || null);
              setIsEditorOpen(true);
            }}
            onPreviewCard={(slug) => setPreviewingSlug(slug)}
            onDeleteCard={handleDeleteCard}
            onDuplicateCard={handleDuplicateCard}
            onToggleStatus={handleToggleCardStatus}
          />
        )}

        {activeTab === 'shop' && (
          <ShopView
            products={initialProducts}
            cart={cart}
            orders={orders}
            organization={organization}
            onAddToCart={handleAddToCart}
            onUpdateCartQty={handleUpdateCartQty}
            onRemoveFromCart={handleRemoveFromCart}
            onCheckout={handleCheckout}
          />
        )}

        {activeTab === 'directory' && (
          <PublicDirectoryView
            organization={organization}
            cards={cards}
            onSelectCard={(slug) => setPreviewingSlug(slug)}
            onBackToApp={() => setActiveTab('dashboard')}
          />
        )}

        {activeTab === 'services' && (
          <ServicesView
            organization={organization}
            onRequestService={(srv) => alert(`Request received for ${srv}!`)}
          />
        )}

        {activeTab === 'team' && (
          <TeamStaffView
            staff={staff}
            cards={cards}
            totalSeats={organization.totalCardSlots}
            onAddStaff={handleAddStaff}
            onRemoveStaff={handleRemoveStaff}
            onUpdatePermissions={handleUpdateStaffPermissions}
          />
        )}

        {activeTab === 'reviews' && (
          <ReviewsView
            reviews={reviews}
            cards={cards}
            onToggleReviewStatus={handleToggleReviewStatus}
            onReplyToReview={handleReplyToReview}
          />
        )}

        {activeTab === 'settings' && (
          <OrgSettingsView
            organization={organization}
            onUpdateOrg={setOrganization}
          />
        )}
      </main>

      {/* Card Editor Modal */}
      <CardEditorModal
        isOpen={isEditorOpen}
        card={editorCard}
        onClose={() => setIsEditorOpen(false)}
        onSave={handleSaveCard}
      />

      {/* Persistent Floating Navigation & Multi-Login Dock */}
      <FloatingMenu
        activeTab={activeTab}
        onSelectTab={setActiveTab}
        currentRole={currentPersona.roleType}
        currentPersona={currentPersona}
        onSelectPersona={setCurrentPersona}
        cart={cart}
      />
    </div>
  );
}
export default App;
