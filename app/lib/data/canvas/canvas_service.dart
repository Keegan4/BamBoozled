import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/app_database.dart';
import '../repositories/task_repository.dart';
import 'canvas_feed.dart';

/// Downloads a feed. Replaced in tests.
typedef FeedFetcher = Future<String> Function(Uri uri);

Future<String> fetchFeedOverHttp(Uri uri) async {
  final http.Response response;
  try {
    response = await http.get(uri).timeout(const Duration(seconds: 30));
  } catch (_) {
    throw const CanvasFeedException('We couldn’t reach Canvas. Check your internet connection and try again.');
  }
  if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
    throw const CanvasFeedException(
      'Canvas didn’t recognise that link. Copy the Calendar Feed link from Canvas again and paste it here.',
    );
  }
  if (response.statusCode != 200) {
    throw CanvasFeedException('Canvas didn’t answer properly (error ${response.statusCode}). Try again later.');
  }
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}

/// Name of the Supabase Edge Function in supabase/functions that fetches feeds for the web app.
const canvasFeedFunction = 'canvas-feed';

/// The web version can't read the feed directly: browsers block a page from reading another site
/// (Canvas) unless that site allows it, and Canvas doesn't. So the web app asks your own Supabase
/// project to fetch it (supabase/functions/canvas-feed), which needs the user to be signed in.
Future<String> fetchFeedViaSupabase(SupabaseClient? client, Uri uri) async {
  if (client == null || client.auth.currentUser == null) {
    throw const CanvasFeedException(
      'In the web version, Canvas works once you’re signed in. Go to Settings → Sign in to sync first.',
    );
  }
  try {
    final response = await client.functions
        .invoke(canvasFeedFunction, body: {'url': uri.toString()})
        .timeout(const Duration(seconds: 40));
    final data = response.data;
    if (data is String) return data;
    throw const CanvasFeedException('Canvas didn’t answer properly. Try again later.');
  } on FunctionException catch (e) {
    final details = e.details;
    final reason = details is Map ? details['reason'] : null;
    throw CanvasFeedException(switch (reason) {
      'not_a_feed' =>
        'That isn’t a Canvas Calendar Feed link. In Canvas, open Calendar, choose Calendar Feed, '
            'and copy the link.',
      'not_recognised' =>
        'Canvas didn’t recognise that link. Copy the Calendar Feed link from Canvas again and paste it here.',
      'unreachable' => 'We couldn’t reach Canvas. Try again later.',
      _ when e.status == 404 =>
        'The web version needs the canvas-feed function in your Supabase project. See “Canvas” in the README.',
      _ => 'Canvas didn’t answer properly (error ${e.status}). Try again later.',
    });
  } on CanvasFeedException {
    rethrow;
  } catch (_) {
    throw const CanvasFeedException('We couldn’t reach Canvas. Check your internet connection and try again.');
  }
}

/// Where the Canvas connection stands. Kept on this device only: the feed link works like a
/// password for the calendar, so it is never uploaded.
class CanvasStatus {
  const CanvasStatus({this.feedUrl, this.lastSyncedAt, this.lastError, this.itemCount = 0});

  final String? feedUrl;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final int itemCount;

  bool get connected => feedUrl != null;
  String? get host => feedUrl == null ? null : Uri.tryParse(feedUrl!)?.host;

  static const key = 'canvas';

  static CanvasStatus fromSetting(String? value) {
    if (value == null) return const CanvasStatus();
    try {
      final j = jsonDecode(value) as Map<String, dynamic>;
      return CanvasStatus(
        feedUrl: j['url'] as String?,
        lastSyncedAt: j['synced'] == null ? null : DateTime.parse(j['synced'] as String),
        lastError: j['error'] as String?,
        itemCount: (j['count'] as int?) ?? 0,
      );
    } catch (_) {
      return const CanvasStatus();
    }
  }

  String toSetting() =>
      jsonEncode({'url': feedUrl, 'synced': lastSyncedAt?.toIso8601String(), 'error': lastError, 'count': itemCount});
}

/// Connects to a Canvas calendar feed and keeps the tasks in step with it.
class CanvasService {
  CanvasService({required this.db, required this.repo, FeedFetcher? fetch, DateTime Function()? clock})
    : _fetch = fetch ?? fetchFeedOverHttp,
      _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final TaskRepository repo;
  final FeedFetcher _fetch;
  final DateTime Function() _clock;
  Future<CanvasImportResult?>? _running;

  Future<CanvasStatus> status() async => CanvasStatus.fromSetting(await db.getSetting(CanvasStatus.key));

  Future<void> _save(CanvasStatus s) => db.setSetting(CanvasStatus.key, s.toSetting());

  /// Checks the link, imports the feed and remembers the link. Throws [CanvasFeedException] with a
  /// message for the user when it doesn't work; nothing is saved then.
  Future<CanvasImportResult> connect(String pasted) async {
    final uri = canvasFeedUri(pasted);
    if (uri == null) {
      throw const CanvasFeedException(
        'That doesn’t look like a link. In Canvas, open Calendar, choose Calendar Feed, and copy the link.',
      );
    }
    final items = parseCanvasFeed(await _fetch(uri));
    final result = await repo.applyCanvasItems(items, restoreDeleted: true);
    await _save(CanvasStatus(feedUrl: uri.toString(), lastSyncedAt: _clock(), itemCount: result.total));
    return result;
  }

  /// Reads the feed again. Problems are recorded for the Settings page instead of thrown. Returns
  /// null when not connected, when it failed, or when the feed was read in the last few minutes
  /// (unless [force], as for the "Update now" button). A refresh already running is shared.
  Future<CanvasImportResult?> refresh({bool force = false}) async {
    if (!force) {
      final last = (await status()).lastSyncedAt;
      if (last != null && _clock().difference(last).abs() < const Duration(minutes: 5)) return null;
    }
    return _running ??= _refresh().whenComplete(() => _running = null);
  }

  Future<CanvasImportResult?> _refresh() async {
    final current = await status();
    final url = current.feedUrl;
    if (url == null) return null;
    try {
      final result = await repo.applyCanvasItems(parseCanvasFeed(await _fetch(Uri.parse(url))));
      if ((await status()).feedUrl == url) {
        await _save(CanvasStatus(feedUrl: url, lastSyncedAt: _clock(), itemCount: result.total));
      }
      return result;
    } catch (e) {
      if ((await status()).feedUrl == url) {
        await _save(
          CanvasStatus(
            feedUrl: url,
            lastSyncedAt: current.lastSyncedAt,
            itemCount: current.itemCount,
            lastError: e is CanvasFeedException ? e.message : 'Couldn’t update from Canvas — will try again.',
          ),
        );
      }
      return null;
    }
  }

  /// Forgets the link and removes everything that came from Canvas.
  Future<int> disconnect() async {
    await db.setSetting(CanvasStatus.key, null);
    return repo.removeCanvasTasks();
  }
}
