import 'package:flutter/material.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/utilities/validators.dart';
import '../../../../shared/widgets/state_views.dart';

/// 403/404/410 on a public resource. These are shown identically so the
/// visitor cannot tell whether a card exists, is disabled or is private.
bool isUnavailableError(Object error) {
  final kind = AppException.from(error).kind;
  return kind == AppErrorKind.forbidden ||
      kind == AppErrorKind.notFound ||
      kind == AppErrorKind.gone;
}

class UnavailableView extends StatelessWidget {
  const UnavailableView({super.key, this.title = "This card isn't available"});

  final String title;

  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.contact_page_outlined,
        title: title,
        message: 'Check the link, or ask the person who shared it for a new one.',
      );
}

/// Network image restricted to http(s) URLs with a graceful fallback.
class SafeNetworkImage extends StatelessWidget {
  const SafeNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    this.fallback,
    this.width,
    this.height,
  });

  final String? url;
  final BoxFit fit;
  final String? semanticLabel;
  final Widget? fallback;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final fb = fallback ??
        ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SizedBox(width: width, height: height),
        );
    if (u == null || !Validators.isSafeWebUrl(u)) return fb;
    return Image.network(
      u,
      fit: fit,
      width: width,
      height: height,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      errorBuilder: (_, _, _) => fb,
    );
  }
}

/// Circular profile image with initials fallback.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 96,
    this.ringColor,
  });

  final String name;
  final String? url;
  final double size;
  final Color? ringColor;

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: scheme.primaryContainer,
      child: Text(
        initials(name),
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
        ),
        textScaler: TextScaler.noScaling,
      ),
    );
    return Semantics(
      image: true,
      label: 'Photo of $name',
      excludeSemantics: true,
      child: Container(
        padding: ringColor == null ? null : const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, color: ringColor),
        child: ClipOval(
          child: SafeNetworkImage(
            url: url,
            width: size,
            height: size,
            fallback: fallback,
          ),
        ),
      ),
    );
  }
}
