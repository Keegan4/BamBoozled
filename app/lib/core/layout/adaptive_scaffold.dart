import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/tasks/task_editor.dart';
import '../theme/colors.dart';
import '../theme/panda_theme.dart';
import '../widgets/panda_mascot.dart';
import 'breakpoints.dart';

class NavDestination {
  const NavDestination(this.path, this.label, this.icon, this.selectedIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const destinations = [
  NavDestination('/', 'Home', Icons.home_outlined, Icons.home_rounded),
  NavDestination('/calendar', 'Calendar', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  NavDestination('/notes', 'Notes', Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded),
  NavDestination('/settings', 'Settings', Icons.tune_rounded, Icons.tune_rounded),
];

/// App frame: a side rail on tablet/desktop, a bottom bar and a big "+"
/// button on phones.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index {
    final i = destinations.indexWhere((d) => d.path != '/' && location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isPhone(context)) {
      return Scaffold(
        body: SafeArea(bottom: false, child: child),
        floatingActionButton: location == '/' || location == '/tasks'
            ? FloatingActionButton.large(
                onPressed: () => showTaskEditor(context),
                tooltip: 'Add task',
                backgroundColor: context.panda.bamboo,
                foregroundColor: context.panda.onBamboo,
                shape: const CircleBorder(),
                child: const Icon(Icons.add_rounded, size: 32),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => context.go(destinations[i].path),
          backgroundColor: context.panda.surface,
          indicatorColor: context.panda.bambooTint,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => PandaText.captionStrong.copyWith(
              color: s.contains(WidgetState.selected) ? context.panda.bambooDark : context.panda.muted,
            ),
          ),
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: Icon(d.icon, color: context.panda.muted),
                selectedIcon: Icon(d.selectedIcon, color: context.panda.bambooDark),
                label: d.label,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          _Rail(index: _index),
          Expanded(child: SafeArea(left: false, child: child)),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => Container(
    width: 104,
    decoration: BoxDecoration(
      color: context.panda.surface,
      border: Border(right: BorderSide(color: context.panda.line)),
    ),
    child: SafeArea(
      right: false,
      child: Column(
        children: [
          const SizedBox(height: 24),
          Tooltip(
            message: 'BamBoozled',
            child: GestureDetector(onTap: () => context.go('/'), child: const PandaMascot(size: 52)),
          ),
          const SizedBox(height: 24),
          for (final (i, d) in destinations.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RailItem(destination: d, selected: i == index),
            ),
        ],
      ),
    ),
  );
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.destination, required this.selected});
  final NavDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.panda.bambooDark : context.panda.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? context.panda.bambooTint : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go(destination.path),
          child: Container(
            width: 80,
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? destination.selectedIcon : destination.icon, color: color),
                const SizedBox(height: 4),
                Text(destination.label, style: PandaText.captionStrong.copyWith(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
