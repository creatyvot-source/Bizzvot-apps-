import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../shared/models/card.dart';
import '../../domain/display_sections.dart';
import '../../domain/media_rules.dart';
import 'card_preview.dart';

/// Titled group of editor fields.
class EditorSection extends StatelessWidget {
  const EditorSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.color,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: color,
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Vertical gap between fields.
const fieldGap = SizedBox(height: AppSpacing.md);

/// Profile photo / cover / logo slot with upload progress.
class ImageSlotTile extends StatelessWidget {
  const ImageSlotTile({
    super.key,
    required this.label,
    required this.url,
    required this.onPick,
    required this.onRemove,
    this.progress,
    this.enabled = true,
  });

  final String label;
  final String? url;

  /// Non-null while uploading (0..1).
  final double? progress;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uploading = progress != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: 56,
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: url == null
                    ? Icon(Icons.image_outlined, color: theme.colorScheme.outline)
                    : Image.network(
                        url!,
                        fit: BoxFit.cover,
                        semanticLabel: '$label preview',
                        errorBuilder: (_, _, _) =>
                            Icon(Icons.broken_image_outlined, color: theme.colorScheme.outline),
                      ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleSmall),
                if (uploading)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: LinearProgressIndicator(
                      value: progress! > 0 ? progress : null,
                      semanticsLabel: 'Uploading $label',
                    ),
                  )
                else
                  Text(
                    url == null ? 'Not set · JPG, PNG or WebP up to 5 MB' : 'Uploaded',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: url == null ? 'Upload $label' : 'Replace $label',
            onPressed: enabled && !uploading ? onPick : null,
            icon: Icon(url == null ? Icons.upload_outlined : Icons.sync),
          ),
          if (url != null)
            IconButton(
              tooltip: 'Remove $label',
              onPressed: enabled && !uploading ? onRemove : null,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

/// Social / custom link list with add, edit, remove and drag-to-reorder.
class LinkListEditor extends StatelessWidget {
  const LinkListEditor({
    super.key,
    required this.title,
    required this.links,
    required this.onChanged,
    required this.social,
  });

  final String title;
  final List<CardLink> links;
  final ValueChanged<List<CardLink>> onChanged;

  /// Social links pick a platform; custom links need a label.
  final bool social;

  Future<void> _edit(BuildContext context, {CardLink? existing, int? index}) async {
    final result = await showDialog<CardLink>(
      context: context,
      builder: (_) => LinkDialog(social: social, existing: existing),
    );
    if (result == null) return;
    final next = [...links];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        if (links.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No links yet.', style: theme.textTheme.bodySmall),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: links.length,
            onReorderItem: (from, to) {
              final next = [...links];
              next.insert(to, next.removeAt(from));
              onChanged(next);
            },
            itemBuilder: (context, i) {
              final l = links[i];
              return ListTile(
                key: ObjectKey(l),
                contentPadding: EdgeInsets.zero,
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const Tooltip(
                    message: 'Drag to reorder',
                    child: SizedBox.square(
                      dimension: AppSpacing.minTap,
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                ),
                title: Text(l.label ?? SocialPlatforms.label(l.type)),
                subtitle: Text(l.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit link',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _edit(context, existing: l, index: i),
                    ),
                    IconButton(
                      tooltip: 'Remove link',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onChanged([...links]..removeAt(i)),
                    ),
                  ],
                ),
              );
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: Text(social ? 'Add social link' : 'Add custom link'),
          ),
        ),
      ],
    );
  }
}

abstract final class SocialPlatforms {
  static const all = <String, String>{
    'linkedin': 'LinkedIn',
    'instagram': 'Instagram',
    'facebook': 'Facebook',
    'x': 'X (Twitter)',
    'youtube': 'YouTube',
    'tiktok': 'TikTok',
    'github': 'GitHub',
    'telegram': 'Telegram',
    'pinterest': 'Pinterest',
    'behance': 'Behance',
    'other': 'Other',
  };

  static String label(String type) => all[type] ?? (type == 'custom' ? 'Link' : type);
}

class LinkDialog extends StatefulWidget {
  const LinkDialog({super.key, required this.social, this.existing});

  final bool social;
  final CardLink? existing;

  @override
  State<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<LinkDialog> {
  final _form = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late final _url = TextEditingController(text: widget.existing?.url ?? 'https://');
  late String _type = widget.social
      ? (SocialPlatforms.all.containsKey(widget.existing?.type) ? widget.existing!.type : 'linkedin')
      : 'custom';

  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final label = _label.text.trim();
    Navigator.of(context).pop(CardLink(
      id: widget.existing?.id,
      type: _type,
      url: _url.text.trim(),
      label: label.isEmpty ? null : label,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add link' : 'Edit link'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.social) ...[
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Platform'),
                items: [
                  for (final e in SocialPlatforms.all.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              fieldGap,
            ],
            TextFormField(
              controller: _label,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: widget.social ? 'Label (optional)' : 'Label',
              ),
              validator: widget.social
                  ? null
                  : (v) => (v == null || v.trim().isEmpty) ? 'Label is required' : null,
            ),
            fieldGap,
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Link (https://)'),
              validator: MediaRules.validateHttpsLink,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Done')),
      ],
    );
  }
}

/// Asks for a YouTube URL and validates it.
Future<String?> askYoutubeUrl(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _YoutubeDialog(),
    );

class _YoutubeDialog extends StatefulWidget {
  const _YoutubeDialog();

  @override
  State<_YoutubeDialog> createState() => _YoutubeDialogState();
}

class _YoutubeDialogState extends State<_YoutubeDialog> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.of(context).pop(_url.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add YouTube video'),
        scrollable: true,
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'YouTube link',
              hintText: 'https://www.youtube.com/watch?v=…',
            ),
            validator: MediaRules.validateYoutube,
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Add')),
        ],
      );
}

/// Preset brand colors + free hex entry.
class BrandColorPicker extends StatelessWidget {
  const BrandColorPicker({super.key, required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  static const presets = <(String, String)>[
    ('#1F4FD8', 'Bizzvot blue'),
    ('#0F766E', 'Teal'),
    ('#15803D', 'Green'),
    ('#B45309', 'Amber'),
    ('#B91C1C', 'Red'),
    ('#BE185D', 'Pink'),
    ('#6D28D9', 'Purple'),
    ('#111827', 'Charcoal'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim().toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (hex, name) in presets)
              Semantics(
                button: true,
                selected: current == hex,
                label: 'Brand color $name',
                excludeSemantics: true,
                child: InkResponse(
                  onTap: () {
                    controller.text = hex;
                    onChanged();
                  },
                  radius: 24,
                  child: SizedBox.square(
                    dimension: AppSpacing.minTap,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: parseHexColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: current == hex ? scheme.onSurface : scheme.outlineVariant,
                            width: current == hex ? 3 : 1,
                          ),
                        ),
                        child: current == hex
                            ? Icon(Icons.check, size: 18, color: onColor(parseHexColor(hex)!))
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        fieldGap,
        TextFormField(
          controller: controller,
          autocorrect: false,
          maxLength: 7,
          decoration: InputDecoration(
            labelText: 'Brand color (hex)',
            hintText: '#1F4FD8',
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: parseHexColor(controller.text) ?? Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outline),
                ),
              ),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return null;
            return parseHexColor(v) == null || !v.trim().startsWith('#')
                ? 'Use a hex color like #1F4FD8'
                : null;
          },
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

/// Reorderable list of public sections with show/hide switches.
class SectionOrderEditor extends StatelessWidget {
  const SectionOrderEditor({
    super.key,
    required this.order,
    required this.toggles,
    required this.onReorder,
    required this.onToggle,
  });

  final List<String> order;
  final Map<String, bool> toggles;
  final ValueChanged<List<String>> onReorder;
  final void Function(String key, bool visible) onToggle;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: order.length,
      onReorderItem: (from, to) {
        final next = [...order];
        next.insert(to, next.removeAt(from));
        onReorder(next);
      },
      itemBuilder: (context, i) {
        final key = order[i];
        final visible = DisplaySections.isVisible(toggles, key);
        return ListTile(
          key: ValueKey('section-$key'),
          contentPadding: EdgeInsets.zero,
          leading: ReorderableDragStartListener(
            index: i,
            child: const Tooltip(
              message: 'Drag to reorder',
              child: SizedBox.square(
                dimension: AppSpacing.minTap,
                child: Icon(Icons.drag_indicator),
              ),
            ),
          ),
          title: Text(DisplaySections.label(key)),
          subtitle: Text(visible ? 'Shown' : 'Hidden'),
          trailing: Switch(
            value: visible,
            onChanged: (v) => onToggle(key, v),
          ),
        );
      },
    );
  }
}

/// Inherit / Public / Private selector with explanations (plan §7.2–7.3).
class VisibilitySelector extends StatelessWidget {
  const VisibilitySelector({super.key, required this.value, required this.onChanged});

  final CardVisibility value;
  final ValueChanged<CardVisibility>? onChanged;

  static String explain(CardVisibility v) => switch (v) {
        CardVisibility.inherit =>
          'Follows the organization directory setting. Listed only when the directory is public and the card is active.',
        CardVisibility.public =>
          'Listed when the card is active. A private organization directory still hides it.',
        CardVisibility.private => 'Never listed in the public people directory.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<CardVisibility>(
          groupValue: value,
          onChanged: (v) {
            if (v != null) onChanged?.call(v);
          },
          child: Column(
            children: [
              for (final v in CardVisibility.values)
                RadioListTile<CardVisibility>(
                  value: v,
                  enabled: onChanged != null,
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.label),
                  subtitle: Text(explain(v)),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.link, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Hiding a card from the directory does not block its direct link or QR code. '
                'Anyone with the link can still open it while the card is active.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
