import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file. Loads the real Nunito font: Flutter's default test font draws every
/// letter as a wide square, which makes layouts in tests very different from the app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nunito = FontLoader('Nunito');
  for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    nunito.addFont(File('assets/fonts/Nunito-$weight.ttf').readAsBytes().then((b) => ByteData.sublistView(b)));
  }
  await nunito.load();
  await testMain();
}
