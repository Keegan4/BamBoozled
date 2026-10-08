import '../../domain/models/category.dart';
import '../../domain/models/task.dart';

/// One page of rows changed on the server since a cursor.
class RemotePage<T> {
  const RemotePage(this.rows, this.cursor);
  final List<T> rows;

  /// The server timestamp of the last row, to pass to the next fetch.
  final String? cursor;
}

/// The server side of sync. Implemented by [SupabaseRemoteStore]; tests use a fake.
abstract interface class RemoteStore {
  static const pageSize = 500;

  Future<void> upsertCategories(List<Category> categories);
  Future<void> upsertTasks(List<Task> tasks);

  /// Rows changed after [cursor] (all rows when null), oldest first, at most [pageSize].
  Future<RemotePage<Category>> fetchCategoriesSince(String? cursor);
  Future<RemotePage<Task>> fetchTasksSince(String? cursor);

  /// Emits whenever another device changes something.
  Stream<void> changes();
}
