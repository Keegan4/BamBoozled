import 'package:flutter/widgets.dart';

/// Layout sizes: phone (< 600), tablet (600–899) and desktop (≥ 900).
abstract final class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 900.0;

  static bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < tablet;
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktop;
}
