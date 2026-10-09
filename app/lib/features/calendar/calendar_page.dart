import 'package:flutter/material.dart';

import '../../core/layout/breakpoints.dart';
import '../../core/theme/panda_theme.dart';
import '../welcome/widgets/calendar_panel.dart';
import '../welcome/widgets/filter_bar.dart';

/// Full-size calendar with the selected day's tasks.
class CalendarPage extends StatelessWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = Breakpoints.isPhone(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(phone ? 16 : 40, phone ? 20 : 32, phone ? 16 : 40, 40),
      children: [
        Text('Calendar', style: phone ? PandaText.title : PandaText.display),
        const SizedBox(height: 16),
        if (phone) const CompactFilterBar() else const FilterBar(),
        const ActiveFilterBanner(),
        const SizedBox(height: 16),
        const CalendarPanel(),
      ],
    );
  }
}
