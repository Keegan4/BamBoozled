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
      (OptionPillStyle.ink, true) => (context.panda.ink, context.panda.rice, context.panda.ink),
      (OptionPillStyle.tint, true) => (context.panda.bambooTint, context.panda.bambooDark, context.panda.bambooDark),
      _ => (context.panda.surface, context.panda.ink, context.panda.line),
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
///
/// The pill is its own Material, clipped to its rounded shape, so the hover and press highlight
/// follows the curve of the pill instead of showing as a box around it.
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
  Widget build(BuildContext context) => MenuAnchor(
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(context.panda.surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
    ),
    alignmentOffset: const Offset(0, 4),
    menuChildren: [
      for (final e in items.entries)
        MenuItemButton(
          onPressed: () => onSelected(e.key),
          style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(160, 48))),
          leadingIcon: Icon(
            Icons.check_rounded,
            size: 18,
            color: e.key == value ? context.panda.bambooDark : Colors.transparent,
          ),
          child: Text(e.value, style: PandaText.body),
        ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: 'Change $label',
      child: Semantics(
        button: true,
        child: Material(
          color: context.panda.surface,
          shape: StadiumBorder(side: BorderSide(color: context.panda.line, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            hoverColor: context.panda.bambooTint,
            onTap: () => controller.isOpen ? controller.close() : controller.open(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$label: ${items[value]}', style: PandaText.bodyStrong),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
      color: context.panda.surface,
      borderRadius: BorderRadius.circular(PandaSizes.cardRadius),
      border: Border.all(color: context.panda.line),
    ),
    child: child,
  );
}
