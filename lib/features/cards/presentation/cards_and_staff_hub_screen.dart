import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/models/card.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/state_views.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../billing/domain/billing_models.dart';
import '../../billing/presentation/billing_providers.dart';
import '../../staff/domain/staff_draft.dart';
import '../../staff/presentation/staff_providers.dart';
import '../data/share_service.dart';
import '../domain/card_filters.dart';
import 'cards_providers.dart';
import 'widgets/share_helpers.dart';

/// Unified "ID & Staff" Hub replacing the legacy directory tab.
/// Combines Digital Cards management, Staff Members with login status,
/// top Quota banner with "Purchase Extra Seats & Cards", and direct
/// Staff Login & Organization Permissions setup.
class CardsAndStaffHubScreen extends ConsumerStatefulWidget {
  const CardsAndStaffHubScreen({super.key});

  @override
  ConsumerState<CardsAndStaffHubScreen> createState() =>
      _CardsAndStaffHubScreenState();
}

class _CardsAndStaffHubScreenState extends ConsumerState<CardsAndStaffHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _cardSearchController = TextEditingController();
  final _staffSearchController = TextEditingController();
  CardStatusFilter _cardFilter = CardStatusFilter.all;
  String _cardQuery = '';
  String _staffQuery = '';
  bool _exporting = false;
  bool _creatingCard = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cardSearchController.dispose();
    _staffSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      ref.refresh(cardsListProvider.future),
      ref.refresh(staffListProvider.future),
      ref.refresh(billingProvider.future),
    ]);
  }

  Future<void> _createCard() async {
    final titleController = TextEditingController();
    final designationController = TextEditingController();

    final input = await showDialog<({String title, String? designation})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New Digital Card'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Cardholder Name',
                hintText: 'e.g. Rahul Sharma',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: designationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Designation / Title (optional)',
                hintText: 'e.g. Managing Director',
                prefixIcon: Icon(Icons.work_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                final des = designationController.text.trim();
                Navigator.of(ctx).pop((
                  title: title,
                  designation: des.isEmpty ? null : des,
                ));
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (input == null || !mounted) return;
    setState(() => _creatingCard = true);
    try {
      final card = await ref
          .read(cardActionsProvider)
          .create(title: input.title, designation: input.designation);
      if (!mounted) return;
      showMessage(context, 'Card created successfully!');
      context.push(Routes.ownerCardEdit(card.id));
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.kind == AppErrorKind.forbidden) {
        final upgrade = await confirmAction(
          context,
          title: 'Card Limit Reached',
          message: '${e.message}\n\nPurchase extra seats to create more cards.',
          confirmLabel: 'Purchase Extra Seats',
        );
        if (upgrade && mounted) context.push(Routes.ownerSeats);
      } else {
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _creatingCard = false);
    }
  }

  void _copyCardLink(CardModel card) {
    final link = 'https://app.bizzvot.com/card/${card.slug}';
    Clipboard.setData(ClipboardData(text: link));
    HapticFeedback.lightImpact();
    showMessage(context, 'Card public link copied to clipboard!');
  }

  void _copyStaffLogin(StaffEntry staff) {
    final message = '''
👋 Welcome to Bizzvot!
Staff Sign-in credentials for ${staff.name}:
• Email: ${staff.email}
• Portal: https://app.bizzvot.com/staff-login
Log in to view and share your smart digital business card.
''';
    Clipboard.setData(ClipboardData(text: message));
    HapticFeedback.lightImpact();
    showMessage(
      context,
      'Staff login details copied! Ready to send via WhatsApp or SMS.',
    );
  }

  Future<void> _shareAllQrCodes(BuildContext anchor) async {
    if (_exporting) return;
    final origin = shareOriginOf(anchor);
    setState(() => _exporting = true);
    try {
      final (:files, :failed) =
          await ref.read(cardActionsProvider).allQrFiles();
      if (failed > 0 && mounted) {
        showMessage(
          context,
          '$failed QR code${failed == 1 ? '' : 's'} could not be downloaded.',
        );
      }
      if (files.isEmpty) {
        if (mounted) {
          showMessage(context, 'There are no QR codes to share yet.');
        }
        return;
      }
      await ref
          .read(shareServiceProvider)
          .shareFiles(files, text: 'Bizzvot card QR codes', origin: origin);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(cardsListProvider);
    final staffAsync = ref.watch(staffListProvider);
    final billingAsync = ref.watch(billingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ID & Staff Hub'),
        actions: [
          IconButton(
            tooltip: 'Setup Staff Login & Permissions',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => context.push(Routes.ownerStaffPermissions),
          ),
          IconButton(
            tooltip: 'Purchase Extra Seats & Cards',
            icon: const Icon(Icons.add_shopping_cart_outlined),
            onPressed: () => context.push(Routes.ownerSeats),
          ),
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Export all QR codes',
              icon: _exporting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2),
              onPressed: () => _shareAllQrCodes(ctx),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(
                icon: Icon(Icons.badge_outlined, size: 20),
                text: 'ID & Cards',
              ),
              Tab(
                icon: Icon(Icons.people_alt_outlined, size: 20),
                text: 'Staff & Team',
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _createCard();
          } else {
            context.push(Routes.ownerStaffNew);
          }
        },
        icon: _creatingCard
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                _tabController.index == 0
                    ? Icons.add_card_outlined
                    : Icons.person_add_alt_1_outlined,
              ),
        label: Text(_tabController.index == 0 ? 'New Card' : 'Add Staff'),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildQuotaAndPurchaseBanner(
                  cardsCount: cardsAsync.value?.length ?? 0,
                  staffCount: staffAsync.value?.length ?? 0,
                  billingSummary: billingAsync.value,
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Cards List
            _buildCardsTab(cardsAsync),
            // Tab 2: Staff List
            _buildStaffTab(staffAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotaAndPurchaseBanner({
    required int cardsCount,
    required int staffCount,
    BillingSummary? billingSummary,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final paidSeats =
        billingSummary?.paidSeats ?? (cardsCount > 0 ? cardsCount : 3);
    final availableSeats =
        billingSummary?.availableSeats ??
        (paidSeats - staffCount).clamp(0, 99);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFF93C5FD),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_membership,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quota & Active Organization Seats',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1E40AF),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$cardsCount Cards Created · $staffCount Staff Members ($availableSeats seats open)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF1E3A8A),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => context.push(Routes.ownerSeats),
                icon: const Icon(Icons.add_shopping_cart, size: 16),
                label: const Text(
                  'Purchase Seats',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 14,
                color: isDark ? Colors.greenAccent : const Color(0xFF16A34A),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '₹499 first-time activation · ₹199/yr renewal per card & staff seat',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.withValues(alpha: 0.2)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isDark ? Colors.amber : const Color(0xFFF59E0B),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '+ 18% GST & courier extra',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.amberAccent : const Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => context.push(Routes.ownerStaffPermissions),
                child: Text(
                  'Permissions Setup →',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? Colors.lightBlueAccent
                        : const Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- CARDS TAB ---
  Widget _buildCardsTab(AsyncValue<List<CardModel>> cardsAsync) {
    return AsyncValueView<List<CardModel>>(
      value: cardsAsync,
      onRetry: () => ref.invalidate(cardsListProvider),
      data: (allCards) {
        final visibleCards = filterCards(
          allCards,
          query: _cardQuery,
          status: _cardFilter,
        );

        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar
                        TextField(
                          controller: _cardSearchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search by name, title or slug...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _cardQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _cardSearchController.clear();
                                      setState(() => _cardQuery = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _cardQuery = v),
                        ),
                        const SizedBox(height: 8),
                        // Filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final filter in CardStatusFilter.values)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(filter.label),
                                    selected: _cardFilter == filter,
                                    onSelected: (val) {
                                      if (val) {
                                        setState(() => _cardFilter = filter);
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (visibleCards.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                    icon: Icons.badge_outlined,
                    title: 'No cards found',
                    message: allCards.isEmpty
                        ? 'Create your first smart digital business card.'
                        : 'No cards match your filter criteria.',
                    action: FilledButton.icon(
                      onPressed: _createCard,
                      icon: const Icon(Icons.add_card_outlined),
                      label: const Text('Create Card'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final card = visibleCards[index];
                        return _buildCardItem(card);
                      },
                      childCount: visibleCards.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardItem(CardModel card) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardTitle = (card.title != null && card.title!.isNotEmpty)
        ? card.title!
        : (card.staffName ?? 'Digital Card');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    cardTitle.isNotEmpty ? cardTitle[0].toUpperCase() : 'C',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cardTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (card.designation != null &&
                          card.designation!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          card.designation!,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StatusChip(
                            card.isActive ? 'Active' : 'Disabled',
                            tone: card.isActive
                                ? StatusTone.success
                                : StatusTone.neutral,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '/${card.slug}',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Analytics',
                  icon: const Icon(Icons.insights_outlined),
                  onPressed: () =>
                      context.push(Routes.ownerCardAnalytics(card.id)),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        context.push(Routes.ownerCardEdit(card.id)),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Edit Card',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        context.push(Routes.ownerCardShare(card.id)),
                    icon: const Icon(Icons.qr_code_2, size: 16),
                    label: const Text(
                      'Share & QR',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Copy Link',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _copyCardLink(card),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- STAFF TAB ---
  Widget _buildStaffTab(AsyncValue<List<StaffEntry>> staffAsync) {
    return AsyncValueView<List<StaffEntry>>(
      value: staffAsync,
      onRetry: () => ref.invalidate(staffListProvider),
      data: (allStaff) {
        final query = _staffQuery.trim().toLowerCase();
        final visibleStaff = allStaff.where((s) {
          if (query.isEmpty) return true;
          return s.name.toLowerCase().contains(query) ||
              s.email.toLowerCase().contains(query) ||
              (s.phone?.toLowerCase().contains(query) ?? false);
        }).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

        return RefreshIndicator(
          onRefresh: _refreshAll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        TextField(
                          controller: _staffSearchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search staff by name, email or phone...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _staffQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _staffSearchController.clear();
                                      setState(() => _staffQuery = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _staffQuery = v),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (visibleStaff.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyView(
                    icon: Icons.people_outline,
                    title: 'No staff members found',
                    message: allStaff.isEmpty
                        ? 'Add staff members to grant them digital card access and credentials.'
                        : 'No staff members match "$_staffQuery".',
                    action: FilledButton.icon(
                      onPressed: () => context.push(Routes.ownerStaffNew),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add Staff'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final staff = visibleStaff[index];
                        return _buildStaffItem(staff);
                      },
                      childCount: visibleStaff.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStaffItem(StaffEntry staff) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSuspended = staff.isSuspended;
    final p = staff.permissions;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    staff.name.isNotEmpty ? staff.name[0].toUpperCase() : 'S',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              staff.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          StatusChip(
                            isSuspended ? 'Suspended' : 'Active Login',
                            tone: isSuspended
                                ? StatusTone.neutral
                                : StatusTone.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        staff.email,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Assigned card indicator
            if (staff.cards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.badge_outlined, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Card: ${staff.cards.first.title ?? staff.name}${staff.cards.first.designation != null ? ' (${staff.cards.first.designation})' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'No digital card assigned yet',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),

            // Permissions badges
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (p.editCard)
                  const StatusChip('Edit Card', tone: StatusTone.info),
                if (p.manageLinks)
                  const StatusChip('Links', tone: StatusTone.info),
                if (p.viewReviews)
                  const StatusChip('Reviews', tone: StatusTone.info),
                if (p.replyReviews)
                  const StatusChip('Reply', tone: StatusTone.info),
                if (!p.editCard &&
                    !p.manageLinks &&
                    !p.viewReviews &&
                    !p.replyReviews)
                  const StatusChip('View only', tone: StatusTone.neutral),
              ],
            ),

            const Divider(height: 20),

            // Actions row
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => context.push(Routes.ownerStaffPermissions),
                    icon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 16,
                    ),
                    label: const Text(
                      'Permissions',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        context.push(Routes.ownerStaffEdit(staff.id)),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text(
                      'Edit Staff',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Share Login Info',
                  icon: const Icon(Icons.share_outlined, size: 18),
                  onPressed: () => _copyStaffLogin(staff),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
