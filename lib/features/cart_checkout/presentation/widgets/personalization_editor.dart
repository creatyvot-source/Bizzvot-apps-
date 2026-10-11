import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../shared/widgets/feedback.dart';
import '../../../catalog/domain/commerce_models.dart';
import '../../../catalog/domain/physical_models.dart';
import '../../../catalog/presentation/common/commerce_widgets.dart';
import '../../data/personalization_repository.dart';
import '../cart_checkout_providers.dart';

/// Opens the NFC/print personalisation editor for [line]. Returns the new
/// personalisation, or null when dismissed.
Future<LinePersonalization?> showPersonalizationEditor(
  BuildContext context,
  CartLine line,
) {
  return Navigator.of(context).push<LinePersonalization>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PersonalizationEditor(line: line),
    ),
  );
}

class PersonalizationEditor extends ConsumerStatefulWidget {
  const PersonalizationEditor({super.key, required this.line});
  final CartLine line;

  @override
  ConsumerState<PersonalizationEditor> createState() => _PersonalizationEditorState();
}

class _UnitDraft {
  _UnitDraft(UnitPersonalization u)
      : cardId = u.cardId,
        useCardReviewPage = u.useCardReviewPage,
        review = TextEditingController(text: u.reviewUrl ?? ''),
        name = TextEditingController(text: u.printName ?? ''),
        designation = TextEditingController(text: u.printDesignation ?? '');

  String? cardId;
  bool useCardReviewPage;
  final TextEditingController review;
  final TextEditingController name;
  final TextEditingController designation;

  void dispose() {
    review.dispose();
    name.dispose();
    designation.dispose();
  }
}

class _PersonalizationEditorState extends ConsumerState<PersonalizationEditor> {
  final _form = GlobalKey<FormState>();
  late LinePersonalization _initial;
  late bool _assignLater;
  late List<_UnitDraft> _units;
  String? _logoUrl;
  String? _logoId;
  bool _uploading = false;

  PersonalizationSpec get _spec => _initial.spec;

  @override
  void initState() {
    super.initState();
    final p = widget.line.personalization ??
        const LinePersonalization(spec: PersonalizationSpec.none);
    _initial = p.resized(widget.line.quantity).withAtLeastOne();
    _assignLater = _initial.assignLater;
    _units = [for (final u in _initial.units) _UnitDraft(u)];
    final first = _initial.units.firstOrNull;
    _logoUrl = first?.logoUrl;
    _logoId = first?.logoMediaId;
  }

  @override
  void dispose() {
    for (final u in _units) {
      u.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await ref.read(logoPickerProvider).pick();
    if (picked == null || !mounted) return;
    if (picked.bytes.lengthInBytes > 5 * 1024 * 1024) {
      showMessage(context, 'Please choose an image under 5 MB.');
      return;
    }
    setState(() => _uploading = true);
    try {
      final up = await ref.read(personalizationRepositoryProvider).uploadLogo(picked);
      if (mounted) {
        setState(() {
          _logoUrl = up.url;
          _logoId = up.id;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _save(List<LinkableCard> cards) {
    if (!_assignLater && !(_form.currentState?.validate() ?? false)) return;
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final units = [
      for (final u in _units)
        UnitPersonalization(
          cardId: u.cardId,
          cardSlug: cards.where((c) => c.id == u.cardId).firstOrNull?.slug,
          cardLabel: cards.where((c) => c.id == u.cardId).firstOrNull?.name,
          reviewUrl: _spec.target == NfcTarget.review && !u.useCardReviewPage ? t(u.review) : null,
          useCardReviewPage: _spec.target == NfcTarget.review && u.useCardReviewPage,
          printName: _spec.printName ? t(u.name) : null,
          printDesignation: _spec.printDesignation ? t(u.designation) : null,
          logoUrl: _spec.logo ? _logoUrl : null,
          logoMediaId: _spec.logo ? _logoId : null,
        ),
    ];
    final result = _initial.copyWith(assignLater: _assignLater, units: units);
    final problem = result.problem(widget.line.quantity);
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final cardsValue = _spec.target == NfcTarget.none
        ? const AsyncData<List<LinkableCard>>([])
        : ref.watch(linkableCardsProvider);
    final cards = cardsValue.value ?? const <LinkableCard>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personalise'),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: _uploading ? null : () => _save(cards),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: AppSpacing.page,
          children: [
            Text(widget.line.titleSnapshot, style: Theme.of(context).textTheme.titleMedium),
            Text('Quantity: ${widget.line.quantity}'),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _assignLater,
              onChanged: (v) => setState(() => _assignLater = v),
              title: const Text('Assign later'),
              subtitle: const Text(
                'Order now and send the card links and print details to our team later.',
              ),
            ),
            if (cardsValue.hasError && !_assignLater)
              NoticeCard(
                title: 'Couldn’t load your cards',
                message: 'You can still choose “assign later”.',
                tone: StatusTone.warning,
                action: TextButton(
                  onPressed: () => ref.invalidate(linkableCardsProvider),
                  child: const Text('Try again'),
                ),
              ),
            if (!_assignLater) ...[
              if (_spec.logo) _logoSection(),
              for (var i = 0; i < _units.length; i++) _unitSection(i, cards),
            ],
          ],
        ),
      ),
    );
  }

  Widget _logoSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Logo (optional)', subtitle: 'Printed on every unit'),
        Row(
          children: [
            if (_logoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox.square(
                  dimension: 56,
                  child: SafeNetworkImage(url: _logoUrl, semanticLabel: 'Uploaded logo'),
                ),
              ),
            if (_logoUrl != null) const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _pickLogo,
                icon: _uploading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_outlined),
                label: Text(_logoUrl == null ? 'Upload logo' : 'Replace logo'),
              ),
            ),
            if (_logoUrl != null)
              IconButton(
                tooltip: 'Remove logo',
                onPressed: () => setState(() {
                  _logoUrl = null;
                  _logoId = null;
                }),
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              ),
          ],
        ),
      ],
    );
  }

  Widget _unitSection(int i, List<LinkableCard> cards) {
    final u = _units[i];
    final title = _spec.perUnit ? 'Unit ${i + 1} of ${_units.length}' : 'Details';
    final cardPicker = DropdownButtonFormField<String>(
      initialValue: cards.any((c) => c.id == u.cardId) ? u.cardId : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _spec.target == NfcTarget.review ? 'Card whose review page opens' : 'Card the tag opens',
        prefixIcon: const Icon(Icons.badge_outlined),
      ),
      items: [
        for (final c in cards)
          DropdownMenuItem(
            value: c.id,
            child: Text(
              c.designation == null ? c.name : '${c.name} · ${c.designation}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      validator: (v) => v == null ? 'Choose a card' : null,
      onChanged: (v) => setState(() {
        u.cardId = v;
        final card = cards.where((c) => c.id == v).firstOrNull;
        if (card == null) return;
        if (_spec.printName && u.name.text.trim().isEmpty) u.name.text = card.name;
        if (_spec.printDesignation && u.designation.text.trim().isEmpty) {
          u.designation.text = card.designation ?? '';
        }
        if (_spec.target == NfcTarget.review &&
            u.review.text.trim().isEmpty &&
            card.googleReviewUrl != null) {
          u.review.text = card.googleReviewUrl!;
        }
      }),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        if (_spec.target == NfcTarget.card) cardPicker,
        if (_spec.target == NfcTarget.review) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Google review link')),
              ButtonSegment(value: true, label: Text('Card review page')),
            ],
            selected: {u.useCardReviewPage},
            onSelectionChanged: (s) => setState(() => u.useCardReviewPage = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (u.useCardReviewPage)
            cardPicker
          else
            TextFormField(
              controller: u.review,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Google review link',
                hintText: 'https://g.page/r/…',
                prefixIcon: Icon(Icons.link),
              ),
              validator: ShippingValidators.reviewUrl,
            ),
        ],
        if (_spec.printName) ...[
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: u.name,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Name to print'),
          ),
        ],
        if (_spec.printDesignation) ...[
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: u.designation,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Designation to print'),
          ),
        ],
      ],
    );
  }
}
