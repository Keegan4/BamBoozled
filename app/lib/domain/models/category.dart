import 'package:flutter/painting.dart';

/// A colour-coded group of tasks, e.g. "Teaching" or "Admin".
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.color,
    this.sortOrder = 0,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final Color color;
  final int sortOrder;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Category copyWith({String? name, Color? color, int? sortOrder, DateTime? updatedAt, DateTime? deletedAt}) =>
      Category(
        id: id,
        name: name ?? this.name,
        color: color ?? this.color,
        sortOrder: sortOrder ?? this.sortOrder,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.sortOrder == sortOrder &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, name, color, sortOrder, updatedAt, deletedAt);
}
