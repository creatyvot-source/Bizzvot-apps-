import React, { useState } from 'react';
import { ProductItem, CartItem, OrderRecord, Organization } from '../types';
import {
  ShoppingBag,
  Plus,
  Minus,
  Check,
  CreditCard,
  Trash2,
  FileText,
  Sparkles,
  ShieldCheck,
  ArrowRight,
  Package,
  Layers,
  X,
  CheckCircle2,
} from 'lucide-react';

interface Props {
  products: ProductItem[];
  cart: CartItem[];
  orders: OrderRecord[];
  organization: Organization;
  onAddToCart: (product: ProductItem) => void;
  onUpdateCartQty: (productId: string, qty: number) => void;
  onRemoveFromCart: (productId: string) => void;
  onCheckout: (order: OrderRecord) => void;
}

export const ShopView: React.FC<Props> = ({
  products,
  cart,
  orders,
  organization,
  onAddToCart,
  onUpdateCartQty,
  onRemoveFromCart,
  onCheckout,
}) => {
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [isCartOpen, setIsCartOpen] = useState(false);
  const [isCheckingOut, setIsCheckingOut] = useState(false);
  const [activeTab, setActiveTab] = useState<'catalog' | 'orders'>('catalog');

  // Checkout inputs
  const [cardHolder, setCardHolder] = useState('Sarah Jenkins');
  const [cardNumber, setCardNumber] = useState('•••• •••• •••• 4092');
  const [orderSuccess, setOrderSuccess] = useState<OrderRecord | null>(null);

  const filteredProducts = products.filter((p) => {
    if (selectedCategory === 'all') return true;
    return p.category === selectedCategory;
  });

  const cartItemCount = cart.reduce((acc, item) => acc + item.quantity, 0);
  const cartSubtotal = cart.reduce((acc, item) => acc + item.product.price * item.quantity, 0);

  const handlePlaceOrder = (e: React.FormEvent) => {
    e.preventDefault();
    if (cart.length === 0) return;

    const newOrder: OrderRecord = {
      id: `ord_${Date.now()}`,
      orderNumber: `BV-2026-${Math.floor(1000 + Math.random() * 9000)}`,
      date: new Date().toISOString(),
      items: cart.map((i) => ({
        productId: i.product.id,
        productName: i.product.name,
        quantity: i.quantity,
        price: i.product.price,
      })),
      totalAmount: cartSubtotal,
      status: 'completed',
      paymentMethod: `Visa ending in ${cardNumber.slice(-4) || '4092'}`,
      customerName: cardHolder || 'Sarah Jenkins',
      customerEmail: organization.contactEmail,
    };

    onCheckout(newOrder);
    setOrderSuccess(newOrder);
    setIsCheckingOut(false);
  };

  return (
    <div className="space-y-8">
      {/* Shop Header */}
      <div className="bg-white p-6 sm:p-8 rounded-3xl border border-slate-200/80 shadow-sm flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
        <div>
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-indigo-50 text-indigo-700 text-xs font-bold mb-2">
            <Sparkles className="w-3.5 h-3.5" />
            Official Bizzvot Store
          </div>
          <h2 className="text-2xl font-extrabold text-slate-900">Services & NFC Hardware Shop</h2>
          <p className="text-sm text-slate-500 mt-1 max-w-xl">
            Order physical NFC smart cards, expand card slot seats, purchase enterprise add-ons, and manage invoices.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <div className="flex bg-slate-100 p-1 rounded-2xl">
            <button
              onClick={() => setActiveTab('catalog')}
              className={`px-4 py-2 rounded-xl text-xs font-bold transition-all ${
                activeTab === 'catalog'
                  ? 'bg-white text-slate-900 shadow-sm'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Catalog
            </button>
            <button
              onClick={() => setActiveTab('orders')}
              className={`px-4 py-2 rounded-xl text-xs font-bold transition-all ${
                activeTab === 'orders'
                  ? 'bg-white text-slate-900 shadow-sm'
                  : 'text-slate-600 hover:text-slate-900'
              }`}
            >
              Order History ({orders.length})
            </button>
          </div>

          <button
            onClick={() => setIsCartOpen(true)}
            className="relative flex items-center gap-2 px-5 py-2.5 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-xs shadow-md shadow-indigo-600/20 transition-all"
          >
            <ShoppingBag className="w-4 h-4" />
            Cart
            {cartItemCount > 0 && (
              <span className="w-5 h-5 rounded-full bg-amber-400 text-slate-950 font-extrabold text-[11px] flex items-center justify-center">
                {cartItemCount}
              </span>
            )}
          </button>
        </div>
      </div>

      {activeTab === 'catalog' && (
        <div className="space-y-6">
          {/* Category Pills */}
          <div className="flex flex-wrap items-center gap-2">
            {[
              { id: 'all', label: 'All Products & Services' },
              { id: 'nfc_cards', label: 'NFC Smart Cards' },
              { id: 'seats', label: 'Card Seats' },
              { id: 'addons', label: 'Domain & Branding' },
              { id: 'subscriptions', label: 'Plans & Subscriptions' },
            ].map((cat) => (
              <button
                key={cat.id}
                onClick={() => setSelectedCategory(cat.id)}
                className={`px-4 py-2 rounded-2xl text-xs font-semibold transition-all ${
                  selectedCategory === cat.id
                    ? 'bg-indigo-600 text-white shadow-sm'
                    : 'bg-white text-slate-600 hover:bg-slate-50 border border-slate-200'
                }`}
              >
                {cat.label}
              </button>
            ))}
          </div>

          {/* Products Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredProducts.map((prod) => (
              <div
                key={prod.id}
                className="bg-white rounded-3xl border border-slate-200/80 overflow-hidden shadow-sm hover:shadow-md transition-all flex flex-col"
              >
                <div className="relative h-48 bg-slate-100 overflow-hidden">
                  <img
                    src={prod.imageUrl}
                    alt={prod.name}
                    className="w-full h-full object-cover transition-transform duration-500 hover:scale-105"
                  />
                  {prod.badge && (
                    <span className="absolute top-3 left-3 bg-indigo-600/90 backdrop-blur-md text-white text-[11px] font-bold px-3 py-1 rounded-full shadow-sm">
                      {prod.badge}
                    </span>
                  )}
                </div>

                <div className="p-6 flex-1 flex flex-col">
                  <div className="flex items-baseline justify-between mb-1">
                    <h3 className="font-bold text-slate-900 text-base">{prod.name}</h3>
                  </div>

                  <div className="flex items-baseline gap-1.5 mb-3">
                    <span className="text-2xl font-extrabold text-slate-900">
                      ${prod.price.toFixed(2)}
                    </span>
                    <span className="text-xs text-slate-400 font-medium">
                      /{prod.billingPeriod || 'item'}
                    </span>
                  </div>

                  <p className="text-xs text-slate-500 mb-4 leading-relaxed flex-1">
                    {prod.description}
                  </p>

                  <div className="space-y-1.5 mb-6 text-xs text-slate-600">
                    {prod.features.map((feat, i) => (
                      <div key={i} className="flex items-center gap-2">
                        <Check className="w-3.5 h-3.5 text-emerald-500 flex-shrink-0" />
                        <span>{feat}</span>
                      </div>
                    ))}
                  </div>

                  <button
                    onClick={() => {
                      onAddToCart(prod);
                      setIsCartOpen(true);
                    }}
                    className="w-full py-2.5 px-4 rounded-xl bg-slate-900 hover:bg-indigo-600 text-white font-semibold text-xs shadow-sm transition-colors flex items-center justify-center gap-2"
                  >
                    <Plus className="w-4 h-4" />
                    Add to Cart
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'orders' && (
        <div className="bg-white rounded-3xl border border-slate-200/80 overflow-hidden shadow-sm">
          <div className="p-6 border-b border-slate-100">
            <h3 className="font-bold text-slate-900 text-base">Order Invoices & Receipts</h3>
            <p className="text-xs text-slate-500">Track all paid orders, NFC hardware fulfillment and renewals</p>
          </div>

          <div className="divide-y divide-slate-100">
            {orders.map((order) => (
              <div key={order.id} className="p-6 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                <div className="flex items-start gap-4">
                  <div className="w-12 h-12 rounded-2xl bg-indigo-50 text-indigo-600 flex items-center justify-center flex-shrink-0">
                    <Package className="w-6 h-6" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="font-bold text-slate-900 text-sm">{order.orderNumber}</h4>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700">
                        {order.status.toUpperCase()}
                      </span>
                    </div>
                    <p className="text-xs text-slate-500 mt-0.5">
                      {new Date(order.date).toLocaleDateString('en-US', {
                        month: 'short',
                        day: 'numeric',
                        year: 'numeric',
                      })} &bull; Paid via {order.paymentMethod}
                    </p>
                    <div className="text-xs text-slate-600 mt-2 space-y-0.5">
                      {order.items.map((it, idx) => (
                        <span key={idx} className="block text-[11px] text-slate-500">
                          {it.quantity}x {it.productName} (${it.price.toFixed(2)})
                        </span>
                      ))}
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-4 w-full sm:w-auto justify-between sm:justify-end">
                  <div className="text-right">
                    <span className="text-base font-extrabold text-slate-900">
                      ${order.totalAmount.toFixed(2)}
                    </span>
                    <span className="text-[10px] text-slate-400 block">Total Paid</span>
                  </div>

                  <button
                    onClick={() => alert(`Receipt #${order.orderNumber}\nTotal: $${order.totalAmount.toFixed(2)}\nCustomer: ${order.customerName}`)}
                    className="flex items-center gap-1.5 px-3 py-2 rounded-xl border border-slate-200 text-slate-700 hover:bg-slate-50 text-xs font-semibold"
                  >
                    <FileText className="w-3.5 h-3.5" />
                    Receipt
                  </button>
                </div>
              </div>
            ))}

            {orders.length === 0 && (
              <div className="p-12 text-center text-slate-400 text-sm">
                No orders placed yet.
              </div>
            )}
          </div>
        </div>
      )}

      {/* Cart Drawer Modal */}
      {isCartOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-end bg-black/50 backdrop-blur-sm animate-in fade-in duration-200">
          <div className="bg-white w-full max-w-md h-full flex flex-col shadow-2xl p-6 overflow-hidden">
            <div className="flex items-center justify-between pb-4 border-b border-slate-100">
              <div className="flex items-center gap-2">
                <ShoppingBag className="w-5 h-5 text-indigo-600" />
                <h3 className="font-bold text-slate-900 text-lg">Your Cart</h3>
                <span className="text-xs bg-indigo-50 text-indigo-700 font-bold px-2 py-0.5 rounded-full">
                  {cartItemCount}
                </span>
              </div>
              <button
                onClick={() => setIsCartOpen(false)}
                className="p-1 rounded-lg text-slate-400 hover:text-slate-600"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Cart Items */}
            <div className="flex-1 overflow-y-auto py-4 space-y-4">
              {cart.map((item) => (
                <div
                  key={item.product.id}
                  className="flex items-center justify-between gap-3 p-3.5 rounded-2xl border border-slate-100 bg-slate-50"
                >
                  <img
                    src={item.product.imageUrl}
                    alt={item.product.name}
                    className="w-14 h-14 rounded-xl object-cover"
                  />
                  <div className="flex-1 min-w-0">
                    <h4 className="text-xs font-bold text-slate-900 truncate">
                      {item.product.name}
                    </h4>
                    <p className="text-xs font-extrabold text-indigo-600 mt-0.5">
                      ${item.product.price.toFixed(2)}
                    </p>
                  </div>

                  <div className="flex items-center gap-1.5">
                    <button
                      onClick={() => onUpdateCartQty(item.product.id, item.quantity - 1)}
                      className="p-1 rounded-lg bg-white border border-slate-200 text-slate-600 hover:bg-slate-100"
                    >
                      <Minus className="w-3.5 h-3.5" />
                    </button>
                    <span className="text-xs font-bold w-5 text-center">{item.quantity}</span>
                    <button
                      onClick={() => onUpdateCartQty(item.product.id, item.quantity + 1)}
                      className="p-1 rounded-lg bg-white border border-slate-200 text-slate-600 hover:bg-slate-100"
                    >
                      <Plus className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={() => onRemoveFromCart(item.product.id)}
                      className="p-1 text-slate-400 hover:text-red-500 ml-1"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              ))}

              {cart.length === 0 && (
                <div className="text-center py-16 text-slate-400 space-y-2">
                  <ShoppingBag className="w-10 h-10 mx-auto text-slate-300" />
                  <p className="text-sm font-semibold">Your cart is empty</p>
                  <p className="text-xs">Browse the NFC smart cards and seat packs above!</p>
                </div>
              )}
            </div>

            {/* Cart Footer */}
            {cart.length > 0 && (
              <div className="pt-4 border-t border-slate-100 space-y-3">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-slate-500 font-medium">Subtotal</span>
                  <span className="font-extrabold text-slate-900 text-lg">
                    ${cartSubtotal.toFixed(2)}
                  </span>
                </div>
                <button
                  onClick={() => {
                    setIsCartOpen(false);
                    setIsCheckingOut(true);
                  }}
                  className="w-full py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-md shadow-indigo-600/20 transition-all flex items-center justify-center gap-2"
                >
                  Proceed to Checkout &rarr;
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Checkout Modal */}
      {isCheckingOut && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl max-w-md w-full p-6 border border-slate-200 relative">
            <button
              onClick={() => setIsCheckingOut(false)}
              className="absolute top-5 right-5 text-slate-400 hover:text-slate-600"
            >
              <X className="w-5 h-5" />
            </button>

            <h3 className="text-xl font-bold text-slate-900 mb-1">Confirm & Pay</h3>
            <p className="text-xs text-slate-500 mb-4">
              Organization: <span className="font-semibold text-slate-800">{organization.name}</span>
            </p>

            <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 mb-4 space-y-2">
              <div className="flex justify-between text-xs font-semibold text-slate-700">
                <span>Items ({cartItemCount})</span>
                <span>${cartSubtotal.toFixed(2)}</span>
              </div>
              <div className="flex justify-between text-xs text-slate-500">
                <span>Express Shipping</span>
                <span className="text-emerald-600 font-medium">Free</span>
              </div>
              <div className="border-t border-slate-200 pt-2 flex justify-between text-sm font-extrabold text-slate-900">
                <span>Total Due</span>
                <span>${cartSubtotal.toFixed(2)}</span>
              </div>
            </div>

            <form onSubmit={handlePlaceOrder} className="space-y-4">
              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Cardholder Name
                </label>
                <input
                  type="text"
                  required
                  value={cardHolder}
                  onChange={(e) => setCardHolder(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-700 mb-1">
                  Corporate Card Number
                </label>
                <input
                  type="text"
                  required
                  value={cardNumber}
                  onChange={(e) => setCardNumber(e.target.value)}
                  className="w-full px-4 py-2.5 rounded-xl border border-slate-200 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-600 font-mono"
                />
              </div>

              <div className="flex items-center gap-2 text-[11px] text-slate-400">
                <ShieldCheck className="w-4 h-4 text-emerald-500" />
                <span>256-bit encrypted checkout with Stripe Bizzvot payments</span>
              </div>

              <button
                type="submit"
                className="w-full py-3.5 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm shadow-lg shadow-indigo-600/30 transition-all flex items-center justify-center gap-2"
              >
                <CreditCard className="w-4 h-4" />
                Authorize Payment (${cartSubtotal.toFixed(2)})
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Order Success Modal */}
      {orderSuccess && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-200">
          <div className="bg-white rounded-3xl shadow-2xl max-w-md w-full p-6 text-center border border-slate-200">
            <CheckCircle2 className="w-14 h-14 text-emerald-500 mx-auto mb-3" />
            <h3 className="text-xl font-bold text-slate-900">Payment Successful!</h3>
            <p className="text-xs text-slate-500 mt-1">
              Order #{orderSuccess.orderNumber} has been verified and registered to {organization.name}.
            </p>

            <div className="my-5 p-4 bg-slate-50 rounded-2xl text-left text-xs space-y-1.5 border border-slate-200">
              <div className="flex justify-between">
                <span className="text-slate-500">Order Number:</span>
                <span className="font-bold text-slate-800">{orderSuccess.orderNumber}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Total Paid:</span>
                <span className="font-bold text-slate-800">${orderSuccess.totalAmount.toFixed(2)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Payment:</span>
                <span className="font-bold text-slate-800">{orderSuccess.paymentMethod}</span>
              </div>
            </div>

            <button
              onClick={() => setOrderSuccess(null)}
              className="w-full py-3 rounded-2xl bg-indigo-600 hover:bg-indigo-700 text-white font-bold text-sm transition-all shadow-md shadow-indigo-600/20"
            >
              Continue to Dashboard
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
