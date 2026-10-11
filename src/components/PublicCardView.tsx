import React, { useState } from 'react';
import { DigitalCard, CardReview } from '../types';
import {
  Phone,
  Mail,
  MapPin,
  Share2,
  Download,
  Star,
  ExternalLink,
  MessageSquare,
  QrCode,
  ArrowLeft,
  Briefcase,
  FileText,
  Image as ImageIcon,
  CheckCircle2,
  Calendar,
  Send,
  X,
} from 'lucide-react';
import { downloadVCard } from '../utils/vcard';
import { CardQRCodeModal } from './CardQRCodeModal';

interface Props {
  card: DigitalCard;
  reviews: CardReview[];
  onBack?: () => void;
  onAddReview: (review: Omit<CardReview, 'id' | 'date' | 'status'>) => void;
  onTrackAction?: (cardId: string, actionType: string) => void;
  isStandalone?: boolean;
}

export const PublicCardView: React.FC<Props> = ({
  card,
  reviews,
  onBack,
  onAddReview,
  onTrackAction,
  isStandalone = false,
}) => {
  const [showQr, setShowQr] = useState(false);
  const [showReviewModal, setShowReviewModal] = useState(false);
  const [copiedLink, setCopiedLink] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'portfolio' | 'reviews'>('info');

  // Review Form state
  const [reviewerName, setReviewerName] = useState('');
  const [reviewerEmail, setReviewerEmail] = useState('');
  const [rating, setRating] = useState(5);
  const [comment, setComment] = useState('');
  const [reviewSubmitted, setReviewSubmitted] = useState(false);

  const cardReviews = reviews.filter((r) => r.cardId === card.id && r.status === 'approved');
  const averageRating =
    cardReviews.length > 0
      ? (cardReviews.reduce((acc, curr) => acc + curr.rating, 0) / cardReviews.length).toFixed(1)
      : '5.0';

  const handleShare = () => {
    onTrackAction?.(card.id, 'share');
    if (navigator.share) {
      navigator.share({
        title: `${card.fullName} - ${card.companyName}`,
        text: `Connect with ${card.fullName} (${card.jobTitle}) on Bizzvot`,
        url: window.location.href,
      }).catch(() => {});
    } else {
      navigator.clipboard.writeText(window.location.href);
      setCopiedLink(true);
      setTimeout(() => setCopiedLink(false), 2000);
    }
  };

  const handleSaveContact = () => {
    onTrackAction?.(card.id, 'save');
    downloadVCard(card);
  };

  const handleSubmitReview = (e: React.FormEvent) => {
    e.preventDefault();
    if (!reviewerName.trim() || !comment.trim()) return;

    onAddReview({
      cardId: card.id,
      authorName: reviewerName,
      authorEmail: reviewerEmail,
      rating,
      comment,
    });

    setReviewSubmitted(true);
    setTimeout(() => {
      setReviewSubmitted(false);
      setShowReviewModal(false);
      setComment('');
      setReviewerName('');
      setReviewerEmail('');
    }, 1800);
  };

  const isDark = card.template === 'modern_dark';

  return (
    <div className={`min-h-screen ${isDark ? 'bg-slate-950 text-slate-100' : 'bg-slate-100 text-slate-900'} py-6 px-4 flex flex-col items-center justify-start`}>
      {/* Top action bar */}
      <div className="w-full max-w-md flex items-center justify-between mb-4">
        {onBack && (
          <button
            onClick={onBack}
            className={`flex items-center gap-1.5 text-xs font-semibold px-3 py-2 rounded-xl transition-all ${
              isDark ? 'bg-slate-800 text-slate-200 hover:bg-slate-700' : 'bg-white text-slate-700 hover:bg-slate-50 shadow-sm border border-slate-200'
            }`}
          >
            <ArrowLeft className="w-4 h-4" />
            Back to Dashboard
          </button>
        )}
        <div className="flex items-center gap-2 ml-auto">
          <button
            onClick={() => setShowQr(true)}
            className={`p-2 rounded-xl transition-all ${
              isDark ? 'bg-slate-800 text-slate-200 hover:bg-slate-700' : 'bg-white text-slate-700 hover:bg-slate-50 shadow-sm border border-slate-200'
            }`}
            title="Scan QR Code"
          >
            <QrCode className="w-4 h-4" />
          </button>
          <button
            onClick={handleShare}
            className={`flex items-center gap-1 text-xs font-semibold px-3 py-2 rounded-xl transition-all ${
              isDark ? 'bg-slate-800 text-slate-200 hover:bg-slate-700' : 'bg-white text-slate-700 hover:bg-slate-50 shadow-sm border border-slate-200'
            }`}
          >
            <Share2 className="w-3.5 h-3.5" />
            {copiedLink ? 'Copied!' : 'Share'}
          </button>
        </div>
      </div>

      {/* Mobile Card Container */}
      <div
        className={`w-full max-w-md rounded-3xl overflow-hidden shadow-2xl transition-all border ${
          isDark
            ? 'bg-slate-900 border-slate-800 text-slate-100'
            : 'bg-white border-slate-200/80 text-slate-900'
        }`}
      >
        {/* Banner Cover */}
        <div className="relative h-44 w-full overflow-hidden bg-gradient-to-r from-indigo-600 to-violet-600">
          {card.coverUrl && (
            <img
              src={card.coverUrl}
              alt="Card cover"
              className="w-full h-full object-cover object-center opacity-85"
            />
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-black/20" />
          
          <div className="absolute top-4 left-4 bg-white/20 backdrop-blur-md px-3 py-1 rounded-full text-[11px] font-semibold text-white tracking-wide border border-white/20 flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
            {card.companyName}
          </div>
        </div>

        {/* Profile Header */}
        <div className="px-6 pb-4 relative">
          <div className="flex justify-between items-end -mt-16 mb-4">
            <div className="relative">
              <img
                src={card.avatarUrl}
                alt={card.fullName}
                className="w-28 h-28 rounded-2xl object-cover border-4 border-white dark:border-slate-900 shadow-xl"
              />
              <span className="absolute bottom-1 right-1 w-5 h-5 rounded-full bg-emerald-500 border-2 border-white dark:border-slate-900 shadow-sm" />
            </div>

            <button
              onClick={() => setShowQr(true)}
              className="p-3 rounded-2xl bg-slate-100 hover:bg-slate-200 text-slate-700 dark:bg-slate-800 dark:text-slate-200 shadow-sm transition-all"
            >
              <QrCode className="w-5 h-5" />
            </button>
          </div>

          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-extrabold tracking-tight">{card.fullName}</h1>
              <CheckCircle2 className="w-5 h-5 text-indigo-600 flex-shrink-0" />
            </div>
            <p className="text-sm font-semibold text-indigo-600 dark:text-indigo-400 mt-0.5">
              {card.jobTitle}
            </p>
            <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5 flex items-center gap-1">
              <Briefcase className="w-3.5 h-3.5" />
              {card.department} &bull; {card.companyName}
            </p>
            {card.location && (
              <p className="text-xs text-slate-500 dark:text-slate-400 mt-0.5 flex items-center gap-1">
                <MapPin className="w-3.5 h-3.5 text-slate-400" />
                {card.location}
              </p>
            )}
          </div>

          {/* Quick Rating Badge */}
          <div className="mt-3 flex items-center gap-2">
            <div className="flex items-center gap-1 bg-amber-500/10 text-amber-600 dark:text-amber-400 px-2.5 py-1 rounded-full text-xs font-bold">
              <Star className="w-3.5 h-3.5 fill-amber-500 text-amber-500" />
              <span>{averageRating}</span>
              <span className="font-normal opacity-75">({cardReviews.length} reviews)</span>
            </div>
            <button
              onClick={() => setShowReviewModal(true)}
              className="text-xs font-semibold text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              Write Review &rarr;
            </button>
          </div>

          {/* Primary Action: Save Contact */}
          <div className="mt-5 grid grid-cols-4 gap-2">
            <button
              onClick={handleSaveContact}
              className="col-span-3 py-3 px-4 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-lg shadow-indigo-600/30 flex items-center justify-center gap-2 transition-all active:scale-[0.98]"
            >
              <Download className="w-4 h-4" />
              Save to Contacts
            </button>
            <a
              href={`tel:${card.phone}`}
              className="col-span-1 py-3 rounded-2xl bg-slate-100 dark:bg-slate-800 hover:bg-slate-200 dark:hover:bg-slate-700 text-slate-800 dark:text-slate-200 flex items-center justify-center transition-all"
              title="Call"
            >
              <Phone className="w-4 h-4" />
            </a>
          </div>

          {/* Contact Bar */}
          <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
            <a
              href={`mailto:${card.email}`}
              className="flex items-center gap-2 p-2.5 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-800/40 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            >
              <Mail className="w-4 h-4 text-indigo-500" />
              <span className="truncate">{card.email}</span>
            </a>
            <a
              href={`tel:${card.phone}`}
              className="flex items-center gap-2 p-2.5 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-800/40 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
            >
              <Phone className="w-4 h-4 text-emerald-500" />
              <span className="truncate">{card.phone}</span>
            </a>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex border-t border-b border-slate-200 dark:border-slate-800 text-xs font-semibold">
          <button
            onClick={() => setActiveTab('info')}
            className={`flex-1 py-3 text-center transition-all border-b-2 ${
              activeTab === 'info'
                ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400 bg-indigo-50/30 dark:bg-indigo-950/20'
                : 'border-transparent text-slate-500 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            Overview
          </button>
          <button
            onClick={() => setActiveTab('portfolio')}
            className={`flex-1 py-3 text-center transition-all border-b-2 ${
              activeTab === 'portfolio'
                ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400 bg-indigo-50/30 dark:bg-indigo-950/20'
                : 'border-transparent text-slate-500 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            Media & Docs ({card.gallery.length + card.documents.length})
          </button>
          <button
            onClick={() => setActiveTab('reviews')}
            className={`flex-1 py-3 text-center transition-all border-b-2 ${
              activeTab === 'reviews'
                ? 'border-indigo-600 text-indigo-600 dark:text-indigo-400 bg-indigo-50/30 dark:bg-indigo-950/20'
                : 'border-transparent text-slate-500 dark:text-slate-400 hover:text-slate-900'
            }`}
          >
            Reviews ({cardReviews.length})
          </button>
        </div>

        {/* Tab Content */}
        <div className="p-6">
          {activeTab === 'info' && (
            <div className="space-y-6">
              {/* Bio */}
              {card.bio && (
                <div>
                  <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500 mb-2">
                    About
                  </h3>
                  <p className="text-sm leading-relaxed text-slate-700 dark:text-slate-300 whitespace-pre-line">
                    {card.bio}
                  </p>
                </div>
              )}

              {/* Action & Social Links */}
              <div>
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500 mb-3">
                  Connect & Links
                </h3>
                <div className="space-y-2.5">
                  {card.links.map((link) => (
                    <a
                      key={link.id}
                      href={link.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex items-center justify-between p-3.5 rounded-2xl border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-800/50 hover:bg-indigo-50/50 dark:hover:bg-indigo-950/30 hover:border-indigo-300 dark:hover:border-indigo-800 transition-all group"
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-xl bg-white dark:bg-slate-700 border border-slate-200 dark:border-slate-600 flex items-center justify-center text-indigo-600 dark:text-indigo-400 shadow-sm">
                          <ExternalLink className="w-4 h-4" />
                        </div>
                        <div>
                          <p className="text-sm font-semibold text-slate-900 dark:text-slate-100 group-hover:text-indigo-600 dark:group-hover:text-indigo-400 transition-colors">
                            {link.label}
                          </p>
                          <p className="text-[11px] text-slate-400 truncate max-w-[220px]">
                            {link.url}
                          </p>
                        </div>
                      </div>
                      <ExternalLink className="w-4 h-4 text-slate-400 group-hover:text-indigo-600 transition-transform group-hover:translate-x-0.5" />
                    </a>
                  ))}
                  {card.links.length === 0 && (
                    <p className="text-xs text-slate-400">No public links added yet.</p>
                  )}
                </div>
              </div>
            </div>
          )}

          {activeTab === 'portfolio' && (
            <div className="space-y-6">
              {/* Gallery */}
              <div>
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500 mb-3 flex items-center gap-1.5">
                  <ImageIcon className="w-3.5 h-3.5" />
                  Gallery & Highlights
                </h3>
                {card.gallery.length > 0 ? (
                  <div className="grid grid-cols-2 gap-3">
                    {card.gallery.map((img) => (
                      <div key={img.id} className="rounded-2xl overflow-hidden border border-slate-200 dark:border-slate-800 group relative">
                        <img
                          src={img.url}
                          alt={img.title}
                          className="w-full h-32 object-cover transition-transform group-hover:scale-105"
                        />
                        <div className="p-2 bg-white/90 dark:bg-slate-900/90 backdrop-blur-sm text-[11px] font-medium text-slate-700 dark:text-slate-300 truncate">
                          {img.title}
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-slate-400 py-4 text-center">No images uploaded.</p>
                )}
              </div>

              {/* Documents */}
              <div>
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500 mb-3 flex items-center gap-1.5">
                  <FileText className="w-3.5 h-3.5" />
                  Documents & Whitepapers
                </h3>
                {card.documents.length > 0 ? (
                  <div className="space-y-2">
                    {card.documents.map((doc) => (
                      <div
                        key={doc.id}
                        className="flex items-center justify-between p-3 rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-800/40"
                      >
                        <div className="flex items-center gap-2.5">
                          <FileText className="w-4 h-4 text-indigo-500" />
                          <div>
                            <p className="text-xs font-semibold">{doc.title}</p>
                            <span className="text-[10px] text-slate-400">{doc.fileSize || 'PDF Document'}</span>
                          </div>
                        </div>
                        <button
                          onClick={() => alert(`Downloading ${doc.title}`)}
                          className="p-1.5 rounded-lg text-slate-400 hover:text-indigo-600 transition-colors"
                        >
                          <Download className="w-4 h-4" />
                        </button>
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-xs text-slate-400 py-4 text-center">No documents attached.</p>
                )}
              </div>
            </div>
          )}

          {activeTab === 'reviews' && (
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h3 className="text-sm font-bold">Client & Peer Testimonials</h3>
                  <p className="text-xs text-slate-400">{cardReviews.length} verified ratings</p>
                </div>
                <button
                  onClick={() => setShowReviewModal(true)}
                  className="px-3 py-1.5 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white text-xs font-bold shadow-sm transition-all flex items-center gap-1"
                >
                  <MessageSquare className="w-3 h-3" />
                  Write Review
                </button>
              </div>

              <div className="space-y-3 pt-2">
                {cardReviews.map((rev) => (
                  <div
                    key={rev.id}
                    className="p-4 rounded-2xl border border-slate-200 dark:border-slate-800 bg-slate-50/50 dark:bg-slate-800/40 space-y-2"
                  >
                    <div className="flex items-center justify-between">
                      <span className="text-xs font-bold text-slate-900 dark:text-slate-100">{rev.authorName}</span>
                      <div className="flex items-center">
                        {[1, 2, 3, 4, 5].map((star) => (
                          <Star
                            key={star}
                            className={`w-3.5 h-3.5 ${
                              star <= rev.rating ? 'fill-amber-400 text-amber-400' : 'text-slate-300 dark:text-slate-600'
                            }`}
                          />
                        ))}
                      </div>
                    </div>
                    <p className="text-xs text-slate-600 dark:text-slate-300 leading-relaxed">"{rev.comment}"</p>
                    {rev.ownerReply && (
                      <div className="mt-2 p-2.5 rounded-xl bg-indigo-50/60 dark:bg-indigo-950/40 border border-indigo-100 dark:border-indigo-900/40 text-[11px] text-indigo-900 dark:text-indigo-200">
                        <span className="font-semibold block mb-0.5">Response from {card.fullName}:</span>
                        {rev.ownerReply}
                      </div>
                    )}
                  </div>
                ))}

                {cardReviews.length === 0 && (
                  <div className="text-center py-8">
                    <Star className="w-8 h-8 text-amber-400 mx-auto mb-2 opacity-50" />
                    <p className="text-xs font-medium text-slate-500">No reviews posted yet</p>
                    <p className="text-[11px] text-slate-400 mt-1">Be the first to share your experience!</p>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Footer Brand */}
        <div className="px-6 py-4 border-t border-slate-100 dark:border-slate-800 text-center bg-slate-50/50 dark:bg-slate-900/80">
          <p className="text-[11px] text-slate-400 flex items-center justify-center gap-1 font-medium">
            Powered by <span className="font-bold text-indigo-600 dark:text-indigo-400">Bizzvot</span> Digital Cards
          </p>
        </div>
      </div>

      {/* QR Code Modal */}
      {showQr && (
        <CardQRCodeModal
          card={card}
          onClose={() => setShowQr(false)}
          onPreview={() => {}}
        />
      )}

      {/* Review Submission Modal */}
      {showReviewModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-white dark:bg-slate-900 rounded-3xl shadow-2xl max-w-md w-full p-6 border border-slate-200 dark:border-slate-800 relative">
            <button
              onClick={() => setShowReviewModal(false)}
              className="absolute top-5 right-5 text-slate-400 hover:text-slate-600 dark:hover:text-slate-200"
            >
              <X className="w-5 h-5" />
            </button>

            {reviewSubmitted ? (
              <div className="text-center py-8 space-y-3">
                <CheckCircle2 className="w-12 h-12 text-emerald-500 mx-auto" />
                <h3 className="text-lg font-bold">Review Submitted!</h3>
                <p className="text-xs text-slate-500">
                  Thank you for your feedback for {card.fullName}.
                </p>
              </div>
            ) : (
              <form onSubmit={handleSubmitReview} className="space-y-4">
                <div>
                  <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100">
                    Review {card.fullName}
                  </h3>
                  <p className="text-xs text-slate-500">
                    Share your experience working with {card.fullName} at {card.companyName}.
                  </p>
                </div>

                {/* Rating selection */}
                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-300 mb-2">
                    Rating
                  </label>
                  <div className="flex items-center gap-2">
                    {[1, 2, 3, 4, 5].map((star) => (
                      <button
                        type="button"
                        key={star}
                        onClick={() => setRating(star)}
                        className="p-1 transition-transform hover:scale-110"
                      >
                        <Star
                          className={`w-7 h-7 ${
                            star <= rating
                              ? 'fill-amber-400 text-amber-400'
                              : 'text-slate-200 dark:text-slate-700'
                          }`}
                        />
                      </button>
                    ))}
                    <span className="text-xs font-bold text-amber-500 ml-2">
                      {rating} out of 5 stars
                    </span>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-300 mb-1">
                    Your Name *
                  </label>
                  <input
                    type="text"
                    required
                    value={reviewerName}
                    onChange={(e) => setReviewerName(e.target.value)}
                    placeholder="e.g. Marcus Vance"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-300 mb-1">
                    Your Email (optional)
                  </label>
                  <input
                    type="email"
                    value={reviewerEmail}
                    onChange={(e) => setReviewerEmail(e.target.value)}
                    placeholder="name@company.com"
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-600 dark:text-slate-300 mb-1">
                    Your Feedback *
                  </label>
                  <textarea
                    required
                    rows={3}
                    value={comment}
                    onChange={(e) => setComment(e.target.value)}
                    placeholder="Describe how your interaction or project went..."
                    className="w-full px-4 py-2.5 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-800 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                </div>

                <button
                  type="submit"
                  className="w-full py-3 rounded-xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-md shadow-indigo-600/20 transition-all flex items-center justify-center gap-2"
                >
                  <Send className="w-4 h-4" />
                  Publish Review
                </button>
              </form>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
