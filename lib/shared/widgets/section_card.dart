import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Card with a compact icon + title header and optional trailing action.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      Insets.md,
      0,
      Insets.md,
      Insets.md,
    ),
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.only(left: Insets.lg, right: Insets.xs),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
