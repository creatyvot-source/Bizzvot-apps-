export type UserRole = 'owner' | 'staff' | 'public';

export type CardTemplate =
  | 'minimal'
  | 'corporate'
  | 'modern_dark'
  | 'profile_hub'
  | 'cover_card'
  | 'review_card';

export type CardStatus = 'active' | 'disabled';
export type CardVisibility = 'inherit' | 'public' | 'private';

export interface CardLink {
  id: string;
  type: 'website' | 'linkedin' | 'x' | 'github' | 'instagram' | 'youtube' | 'whatsapp' | 'calendly' | 'custom';
  label: string;
  url: string;
  icon?: string;
}

export interface MediaDoc {
  id: string;
  title: string;
  url: string;
  fileSize?: string;
}

export interface MediaGalleryItem {
  id: string;
  title: string;
  url: string;
}

export interface CardStats {
  views: number;
  saves: number;
  qrScans: number;
  shares: number;
}

export interface DigitalCard {
  id: string;
  slug: string;
  fullName: string;
  jobTitle: string;
  department: string;
  companyName: string;
  email: string;
  phone: string;
  location: string;
  bio: string;
  avatarUrl: string;
  coverUrl: string;
  template: CardTemplate;
  status: CardStatus;
  visibility: CardVisibility;
  accentColor: string;
  links: CardLink[];
  gallery: MediaGalleryItem[];
  documents: MediaDoc[];
  stats: CardStats;
  assignedStaffId?: string;
  createdAt: string;
  updatedAt: string;
}

export interface StaffMember {
  id: string;
  name: string;
  email: string;
  role: string;
  department: string;
  cardId?: string;
  status: 'active' | 'pending';
  canEditCard: boolean;
  canViewReviews: boolean;
  canViewAnalytics: boolean;
  joinedDate: string;
}

export interface CardReview {
  id: string;
  cardId: string;
  authorName: string;
  authorEmail?: string;
  rating: number; // 1-5
  comment: string;
  date: string;
  status: 'approved' | 'hidden';
  ownerReply?: string;
}

export interface Organization {
  id: string;
  name: string;
  slug: string;
  logoUrl: string;
  plan: string;
  planStatus: 'active' | 'trial' | 'expired';
  trialDaysRemaining?: number;
  planExpiry: string;
  totalCardSlots: number;
  publicDirectoryEnabled: boolean;
  website: string;
  contactEmail: string;
}

export interface ProductItem {
  id: string;
  name: string;
  category: 'nfc_cards' | 'seats' | 'subscriptions' | 'addons';
  price: number;
  currency: string;
  billingPeriod?: 'one-time' | 'monthly' | 'yearly';
  description: string;
  imageUrl: string;
  badge?: string;
  features: string[];
  inStock: boolean;
}

export interface CartItem {
  product: ProductItem;
  quantity: number;
}

export interface OrderRecord {
  id: string;
  orderNumber: string;
  date: string;
  items: {
    productId: string;
    productName: string;
    quantity: number;
    price: number;
  }[];
  totalAmount: number;
  status: 'completed' | 'processing';
  paymentMethod: string;
  invoiceUrl?: string;
  customerName: string;
  customerEmail: string;
}
