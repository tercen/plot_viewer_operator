/// A data factor (column) from a workflow step.
///
/// Factor names follow the convention `namespace.column_name`.
/// The namespace is text before the first dot; shortName is text after the last dot.
class Factor {
  final String name;
  final String type;

  const Factor({required this.name, required this.type});

  /// Namespace prefix (text before first dot), or empty string if none.
  String get namespace =>
      name.contains('.') ? name.substring(0, name.indexOf('.')) : '';

  /// Display name (text after last dot).
  String get shortName =>
      name.contains('.') ? name.substring(name.lastIndexOf('.') + 1) : name;

  /// Whether this factor is numeric (double or int).
  bool get isNumeric => type == 'double' || type == 'int';

  /// Whether this is a system column that should be filtered out.
  /// Names starting with '.', ending with '._rids' or '.tlbId'.
  bool get isSystemColumn =>
      name.startsWith('.') ||
      name.endsWith('._rids') ||
      name.endsWith('.tlbId');
}
