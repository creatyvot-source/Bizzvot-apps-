import React, { useState } from 'react';
import { CardReview, DigitalCard } from '../types';
import {
  Star,
  Search,
  Filter,
  CheckCircle,
  EyeOff,
  Eye,
  MessageSquare,
  CornerDownRight,
  ShieldCheck,
  Send,
} from 'lucide-react';

interface Props {
  reviews: CardReview[];
  cards: DigitalCard[];
  onToggleReviewStatus: (reviewId: string) => void;
  onReplyToReview: (reviewId: string, reply: string) => void;
}

export const ReviewsView: React.FC<Props> = ({
  reviews,
  cards,
  onToggleReviewStatus,
  onReplyToReview,
}) => {
  const [search, setSearch] = useState('');
  const [filterRating, setFilterRating] = useState<number | 'all'>('all');
  const [replyingToId, setReplyingToId] = useState<string | null>(null);
  const [replyText, setReplyText] = useState('');

  const cardMap = new Map(cards.map((c) => [c.id, c]));

  const filteredReviews = reviews.filter((rev) => {
    const card = cardMap.get(rev.cardId);
    const cardName = card?.fullName || '';
    const matchesSearch =
      rev.authorName.toLowerCase().includes(search.toLowerCase()) ||
      rev.comment.toLowerCase().includes(search.toLowerCase()) ||
      cardName.toLowerCase().includes(search.toLowerCase());

    const matchesRating = filterRating === 'all' || rev.rating === filterRating;

    return matchesSearch && matchesRating;
  });

  const handleSendReply = (reviewId: string) => {
    if (!replyText.trim()) return;
    onReplyToReview(reviewId, replyText);
    setReplyingToId(null);
    setReplyText('');
  };

  return (
    <div className="space-y-6">
      <div className="bg-white p-6 rounded-3xl border border-slate-200/80 shadow-sm flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold text-slate-900">Verified Client Reviews</h2>
          <p className="text-sm text-slate-500 mt-1">
            Testimonials and star ratings submitted on your team members' digital business cards.
          </p>
        </div>
      </div>

      {/* Filter and Search */}
      <div className="flex flex-col sm:flex-row items-center gap-3">
        <div className="relative flex-1 w-full">
          <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            type="text"
            placeholder="Search reviews by client name, comment text, or team member..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2.5 rounded-2xl border border-slate-200 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600/20 shadow-sm"
          />
        </div>

        <div className="flex items-center gap-2">
          <select
            value={filterRating.toString()}
            onChange={(e) =>
              setFilterRating(e.target.value === 'all' ? 'all' : parseInt(e.target.value))
            }
            className="px-4 py-2.5 rounded-2xl border border-slate-200 bg-white text-sm font-medium text-slate-700 focus:outline-none shadow-sm"
          >
            <option value="all">All Star Ratings</option>
            <option value="5">5 Stars only</option>
            <option value="4">4 Stars only</option>
            <option value="3">3 Stars only</option>
          </select>
        </div>
      </div>

      {/* Reviews List */}
      <div className="space-y-4">
        {filteredReviews.map((rev) => {
          const card = cardMap.get(rev.cardId);
          const isApproved = rev.status === 'approved';

          return (
            <div
              key={rev.id}
              className={`p-6 rounded-3xl border transition-all bg-white ${
                isApproved ? 'border-slate-200/80 shadow-sm' : 'border-amber-200 bg-amber-50/20'
              }`}
            >
              <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-3 mb-3">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-indigo-50 text-indigo-700 font-bold flex items-center justify-center text-sm border border-indigo-100">
                    {rev.authorName.charAt(0)}
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="font-bold text-slate-900 text-sm">{rev.authorName}</h4>
                      {rev.authorEmail && (
                        <span className="text-xs text-slate-400">({rev.authorEmail})</span>
                      )}
                      <span
                        className={`text-[10px] font-bold px-2 py-0.5 rounded-full uppercase ${
                          isApproved ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'
                        }`}
                      >
                        {rev.status}
                      </span>
                    </div>
                    {card && (
                      <p className="text-xs text-slate-500 mt-0.5">
                        Reviewed for <span className="font-semibold text-slate-700">{card.fullName}</span> ({card.jobTitle})
                      </p>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-1">
                  {[1, 2, 3, 4, 5].map((star) => (
                    <Star
                      key={star}
                      className={`w-4 h-4 ${
                        star <= rev.rating ? 'fill-amber-400 text-amber-400' : 'text-slate-200'
                      }`}
                    />
                  ))}
                  <span className="text-xs font-bold text-slate-700 ml-1.5">{rev.rating}.0</span>
                </div>
              </div>

              <p className="text-sm text-slate-700 leading-relaxed pl-13 my-3">
                "{rev.comment}"
              </p>

              {/* Owner Reply */}
              {rev.ownerReply && (
                <div className="ml-12 mt-3 p-3.5 rounded-2xl bg-slate-50 border border-slate-100 text-xs space-y-1">
                  <div className="flex items-center gap-1.5 font-bold text-indigo-600">
                    <CornerDownRight className="w-3.5 h-3.5" />
                    Official Response
                  </div>
                  <p className="text-slate-600 pl-5">{rev.ownerReply}</p>
                </div>
              )}

              {/* Reply Form */}
              {replyingToId === rev.id && (
                <div className="ml-12 mt-3 p-4 rounded-2xl bg-indigo-50/50 border border-indigo-100 space-y-3">
                  <p className="text-xs font-bold text-indigo-900">
                    Post official reply as {card?.fullName || 'Organization Owner'}
                  </p>
                  <textarea
                    rows={2}
                    value={replyText}
                    onChange={(e) => setReplyText(e.target.value)}
                    placeholder="Type your thank you note or clarification..."
                    className="w-full p-3 rounded-xl border border-indigo-200 bg-white text-xs focus:outline-none focus:ring-2 focus:ring-indigo-600"
                  />
                  <div className="flex items-center justify-end gap-2">
                    <button
                      onClick={() => setReplyingToId(null)}
                      className="px-3 py-1.5 rounded-lg text-xs font-semibold text-slate-600 hover:bg-slate-200/50"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={() => handleSendReply(rev.id)}
                      className="px-4 py-1.5 rounded-lg bg-indigo-600 text-white text-xs font-bold flex items-center gap-1.5 hover:bg-indigo-700"
                    >
                      <Send className="w-3 h-3" />
                      Post Reply
                    </button>
                  </div>
                </div>
              )}

              {/* Actions Footer */}
              <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-xs">
                <span className="text-[11px] text-slate-400">
                  Submitted {new Date(rev.date).toLocaleDateString()}
                </span>

                <div className="flex items-center gap-2">
                  {!rev.ownerReply && replyingToId !== rev.id && (
                    <button
                      onClick={() => {
                        setReplyingToId(rev.id);
                        setReplyText('');
                      }}
                      className="flex items-center gap-1 font-semibold text-indigo-600 hover:text-indigo-800 px-2 py-1 rounded-lg hover:bg-indigo-50 transition-colors"
                    >
                      <MessageSquare className="w-3.5 h-3.5" />
                      Reply
                    </button>
                  )}
                  <button
                    onClick={() => onToggleReviewStatus(rev.id)}
                    className="flex items-center gap-1 font-semibold text-slate-600 hover:text-slate-900 px-2 py-1 rounded-lg hover:bg-slate-100 transition-colors"
                  >
                    {isApproved ? (
                      <>
                        <EyeOff className="w-3.5 h-3.5 text-slate-400" />
                        Hide from Card
                      </>
                    ) : (
                      <>
                        <Eye className="w-3.5 h-3.5 text-emerald-600" />
                        Publish to Card
                      </>
                    )}
                  </button>
                </div>
              </div>
            </div>
          );
        })}

        {filteredReviews.length === 0 && (
          <div className="p-12 text-center bg-white rounded-3xl border border-slate-200 text-slate-400 text-sm">
            No reviews match the selected filter.
          </div>
        )}
      </div>
    </div>
  );
};
