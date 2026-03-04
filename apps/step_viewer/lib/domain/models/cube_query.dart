/// Minimal CubeQuery model (no sci_tercen_client dependency).
///
/// Represents the result of a WASM-managed CubeQuery lifecycle.
/// Deserialized from JSON returned by ggrs_wasm's ensureCubeQuery().
///
/// This eliminates the 500KB sci_tercen_client SDK dependency from step_viewer.
class CubeQueryResult {
  /// Schema IDs by role: "qt", "x_axis", "y_axis", "column", "row"
  final Map<String, String> tables;

  /// Total row count (for progress tracking)
  final int nRows;

  /// Facet dimensions (computed from domain tables)
  final int nColFacets;
  final int nRowFacets;

  const CubeQueryResult({
    required this.tables,
    required this.nRows,
    required this.nColFacets,
    required this.nRowFacets,
  });

  factory CubeQueryResult.fromJson(Map<String, dynamic> json) {
    return CubeQueryResult(
      tables: Map<String, String>.from(json['tables'] as Map),
      nRows: json['n_rows'] as int,
      nColFacets: json['n_col_facets'] as int,
      nRowFacets: json['n_row_facets'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tables': tables,
      'n_rows': nRows,
      'n_col_facets': nColFacets,
      'n_row_facets': nRowFacets,
    };
  }

  @override
  String toString() {
    return 'CubeQueryResult(tables: $tables, nRows: $nRows, '
        'facets: ${nColFacets}x$nRowFacets)';
  }
}
