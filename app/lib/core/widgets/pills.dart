import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/panda_theme.dart';

/// Rounded, 44px-tall selectable pill. Used for category filters and the
/// options on the add-task form.
class OptionPill extends StatelessWidget {
  const OptionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dotColor,
    this.icon,
    this.style = OptionPillStyle.tint,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Category colour dot shown before the label.
  final Color? dotColor;
  final IconData? icon;
  final OptionPillStyle style;

  /// Shows a small × to clear this option.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch ((style, selected)) {
      (OptionPillStyle.ink, true) => (PandaColors.ink, PandaColors.rice, PandaColors.ink),
      (OptionPillStyle.tint, true) => (PandaColors.bambooTint, PandaColors.bambooDark, PandaColors.bambooDark),
      _ => (PandaColors.surface, PandaColors.ink, PandaColors.line),
    };
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: BorderSide(color: border, width: selected && style == OptionPillStyle.tint ? 2 : 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.only(left: 16, right: onRemove != null ? 4 : 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected && style == OptionPillStyle.tint && dotColor == null) ...[
                    Icon(Icons.check_rounded, size: 18, color: fg),
                    const SizedBox(width: 6),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                  ],
                  if (dotColor != null) ...[
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: fg.withValues(alpha: 0.15)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(label, style: PandaText.bodyStrong.copyWith(color: fg)),
                  if (onRemove != null)
                    IconButton(
                      onPressed: onRemove,
                      tooltip: 'Remove $label',
                      icon: Icon(Icons.close_rounded, size: 18, color: fg),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum OptionPillStyle {
  /// Selected = black pill (category filters).
  ink,

  /// Selected = green tint with a tick (form options).
  tint,
}

/// A pill that opens a menu, e.g. "Priority: Any ▾". [T] may be nullable (null = "Any").
class DropdownPill<T> extends StatelessWidget {
  const DropdownPill({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_Choice<T>>(
    tooltip: 'Change $label',
    initialValue: _Choice(value),
    // Values are wrapped because PopupMenuButton never reports a null value, which would
    // make a "null = Any" choice silently do nothing.
    onSelected: (choice) => onSelected(choice.value),
    position: PopupMenuPosition.under,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    itemBuilder: (_) => [
      for (final e in items.entries)
        PopupMenuItem(
          value: _Choice(e.key),
          height: 48,
          child: Text(e.value, style: PandaText.body),
        ),
    ],
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.only(left: 16, right: 10),
      decoration: ShapeDecoration(
        color: PandaColors.surface,
        shape: StadiumBorder(side: BorderSide(color: PandaColors.line, width: 1.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ${items[value]}', style: PandaText.bodyStrong),
          const SizedBox(width: 4),
          const Icon(Icons.expand_more_rounded, size: 20),
        ],
      ),
    ),
  );
}

class _Choice<T> {
  const _Choice(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is _Choice<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// White rounded card used for the main panels.
class PandaCard extends StatelessWidget {
  const PandaCard({super.key, required this.child, this.padding = const EdgeInsets.all(24)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: PandaColors.surface,
      borderRadius: BorderRadius.circular(PandaSizes.cardRadius),
      border: Border.all(color: PandaColors.line),
    ),
    child: child,
  );
}
