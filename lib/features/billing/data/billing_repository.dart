import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/endpoints.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/models/paged.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/commerce_models.dart';
import '../../catalog/domain/idempotency.dart';
import '../../catalog/domain/money.dart';
import '../domain/billing_models.dart';

class BillingRepository {
  BillingRepository(this._api);

  final ApiClient _api;

  /// `GET /organization/billing` (existing).
  Future<BillingSummary> billing() =>
      _api.get(Endpoints.billing, parse: BillingSummary.fromJson);

  static const defaultPlans = [
    Plan(
      id: 'plan-staff-card-activation',
      name: 'Smart Card & Staff Activation',
      billingPeriod: 'first_year',
      price: Money(49900, 'INR'),
      priceLabel: '₹499 + GST',
      description:
          'First-time setup and 1-year smart digital card activation with NFC link, dynamic profile, and staff portal management. (+ 18% GST and ₹99 express courier charge extra for physical smart card delivery).',
      features: [
        'First time activation: ₹499 per card/staff',
        '+ 18% GST extra applicable',
        '+ ₹99 express courier charge for PVC card delivery',
        '1-Year complete validity included',
        'Organization can assign & staff can manage details',
        'Next year renewal at only ₹199/year (+ GST)',
      ],
      recommended: true,
      active: true,
      paymentPolicy: PaymentPolicy.physical,
      purchaseChannels: PurchaseChannels(ios: true, android: true),
    ),
    Plan(
      id: 'plan-yearly-renewal',
      name: 'Yearly Card & Staff Renewal',
      billingPeriod: 'yearly',
      price: Money(19900, 'INR'),
      priceLabel: '₹199 / year + GST',
      description:
          'Annual maintenance and cloud sync for active smart cards & staff seats. Keeps profiles and contact sharing live. (+ 18% GST extra).',
      features: [
        'Annual renewal: ₹199 per card/staff',
        '+ 18% GST extra applicable',
        '365 days cloud profile hosting & NFC sync',
        'Instant contact saving & analytics',
      ],
      active: true,
      paymentPolicy: PaymentPolicy.physical,
      purchaseChannels: PurchaseChannels(ios: true, android: true),
    ),
  ];

  Future<List<Plan>> plans() async {
    try {
      final list = await _api.get(
        Endpoints.catalogPlans,
        parse: (d) =>
            Paged.parse(
                  d,
                  Plan.fromJson,
                  listKeys: const ['plans', 'items', 'data'],
                ).items
                .where((p) => p.id.isNotEmpty && p.active)
                .toList(growable: false),
      );
      if (list.isNotEmpty) return list;
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.network) {
        return defaultPlans;
      }
      if (e.kind == AppErrorKind.unauthenticated) {
        rethrow;
      }
    }
    try {
      final b = await billing();
      final activePlans = b.plans.where((p) => p.active).toList(growable: false);
      return activePlans.isNotEmpty ? activePlans : defaultPlans;
    } catch (_) {
      return defaultPlans;
    }
  }

  /// Server price for [quantity] additional seats on [planId]
  /// (PROPOSED `POST /cart/quote`).
  Future<Quote> quoteSeats({required String planId, required int quantity}) async {
    try {
      return await _api.post(
        Endpoints.cartQuote,
        body: {
          'purpose': 'seats',
          'lines': [
            {
              'itemType': CatalogItemType.plan.name,
              'itemId': planId,
              'quantity': quantity,
            },
          ],
        },
        parse: Quote.fromJson,
      );
    } catch (_) {
      final unitAmount = planId.contains('renewal') ? 19900 : 49900;
      final subtotal = unitAmount * quantity;
      final isPhysical = !planId.contains('renewal');
      final gstAmount = (subtotal * 18) ~/ 100;
      final courierAmount = isPhysical ? 9900 : 0;
      final total = subtotal + gstAmount + courierAmount;
      return Quote(
        id: 'quote-seats-local',
        currency: 'INR',
        subtotal: Money(subtotal, 'INR'),
        taxes: [
          Adjustment(
            label: 'GST (18%)',
            rate: '18%',
            amount: Money(gstAmount, 'INR'),
          ),
        ],
        taxTotal: Money(gstAmount, 'INR'),
        shipping: isPhysical ? Money(courierAmount, 'INR') : null,
        total: Money(total, 'INR'),
        notes: [
          isPhysical
              ? 'Includes 18% GST and ₹99 express courier delivery for physical smart NFC cards.'
              : 'Includes 18% GST. Digital profile renewed instantly.',
        ],
        lines: [
          QuoteLine(
            itemType: CatalogItemType.plan,
            itemId: planId,
            title: planId.contains('renewal')
                ? 'Yearly Card & Staff Renewal'
                : 'Smart Card & Staff Activation',
            quantity: quantity,
            unitPrice: Money(unitAmount, 'INR'),
            lineTotal: Money(subtotal, 'INR'),
            available: true,
          ),
        ],
      );
    }
  }

  /// Starts the seat subscription via the EXISTING `POST /organization/billing`
  /// `{ quantity, planId }`. Returns the hosted checkout, never a success.
  Future<PaymentSession> startSubscription({
    required int quantity,
    required String planId,
    required String idempotencyKey,
  }) => _api.post(
    Endpoints.billing,
    body: {'quantity': quantity, 'planId': planId},
    headers: {idempotencyHeader: idempotencyKey},
    parse: PaymentSession.fromJson,
  );
}

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepository(ref.watch(apiClientProvider)),
);
