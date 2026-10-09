import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a link in the web browser. Tests swap this out.
final linkOpenerProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Opens [link] in the browser, or says so if it can't.
Future<void> openLink(BuildContext context, WidgetRef ref, String link) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.tryParse(link);
  var opened = false;
  try {
    opened = uri != null && await ref.read(linkOpenerProvider)(uri);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn’t open the link. Is a web browser installed?')));
  }
}
