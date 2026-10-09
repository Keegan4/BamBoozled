import 'package:flutter/widgets.dart';

/// Layout sizes: phone (< 600), tablet (600–1099) and desktop (≥ 1100).
///
/// The two-column welcome page needs about 1100px: any narrower and the "Do next" cards get too
/// thin to read, so narrower windows stack the sections in one column instead.
abstract final class Breakpoints {
  static const tablet = 600.0;
  static const desktop = 1100.0;

  static bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < tablet;
  static bool isDesktop(BuildContext context) => MediaQuery.sizeOf(context).width >= desktop;
}
