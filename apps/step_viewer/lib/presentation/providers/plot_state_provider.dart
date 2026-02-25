import 'package:flutter/foundation.dart';
import 'package:widget_library/widget_library.dart';

import '../../di/service_locator.dart';
import '../../domain/services/data_service.dart';
import '../../services/cube_query_service.dart';

/// Manages the plot configuration state: aesthetic bindings, geom type, theme,
/// factor panel visibility, and factor loading from Tercen.
///
/// Axes (x, y) accept a single factor. Facets (row, col) accept multiple.
class PlotStateProvider extends ChangeNotifier {
  final DataService _dataService;

  PlotStateProvider({DataService? dataService})
      : _dataService = dataService ?? serviceLocator<DataService>();

  // --- Factor loading state ---
  int _initGeneration = 0;
  bool _isFactorsLoading = false;
  String? _factorsError;
  List<Factor> _factors = [];
  String? _workflowId;
  String? _stepId;

  bool get isFactorsLoading => _isFactorsLoading;
  String? get factorsError => _factorsError;
  List<Factor> get factors => List.unmodifiable(_factors);
  String? get workflowId => _workflowId;
  String? get stepId => _stepId;

  // --- Plot bindings ---
  Factor? _xBinding;
  Factor? _yBinding;
  final List<Factor> _rowFacetBindings = [];
  final List<Factor> _colFacetBindings = [];
  String _geomType = 'point';
  String _plotTheme = 'gray';
  bool _isFactorPanelOpen = false;

  // --- Viewport (facet index tracking) ---
  int _viewportRowStart = 0;
  int _viewportColStart = 0;
  int _windowRowCount = 0;
  int _windowColCount = 0;
  int _totalRowFacets = 1;
  int _totalColFacets = 1;
  double _cellHeight = 0;
  double _cellWidth = 0;

  // --- Committed state (axis ranges + mappings from last render) ---
  double? _committedXMin;
  double? _committedXMax;
  double? _committedYMin;
  double? _committedYMax;
  List<AxisMappingData> _committedMappings = [];

  Factor? get xBinding => _xBinding;
  Factor? get yBinding => _yBinding;
  List<Factor> get rowFacetBindings => List.unmodifiable(_rowFacetBindings);
  List<Factor> get colFacetBindings => List.unmodifiable(_colFacetBindings);
  String get geomType => _geomType;
  String get plotTheme => _plotTheme;
  bool get isFactorPanelOpen => _isFactorPanelOpen;

  void toggleFactorPanel() {
    _isFactorPanelOpen = !_isFactorPanelOpen;
    notifyListeners();
  }

  /// Called when a step-selected message is received.
  ///
  /// Fetches existing CubeQuery bindings and available factors in parallel.
  /// If the step already has a CubeQuery with a Y binding, those bindings
  /// are restored and rendering starts immediately.
  void onStepSelected(String workflowId, String stepId) {
    _workflowId = workflowId;
    _stepId = stepId;
    _xBinding = null;
    _yBinding = null;
    _rowFacetBindings.clear();
    _colFacetBindings.clear();
    resetViewport();
    _isFactorPanelOpen = true;
    _initStep(workflowId, stepId);
  }

  Future<void> _initStep(String workflowId, String stepId) async {
    final gen = ++_initGeneration;
    _isFactorsLoading = true;
    _factorsError = null;
    notifyListeners();

    try {
      // Fetch factors and existing CQ bindings in parallel
      final results = await Future.wait([
        _dataService.loadFactors(workflowId, stepId),
        serviceLocator<CubeQueryService>().fetchExistingBindings(
          workflowId: workflowId,
          stepId: stepId,
        ),
      ]);

      // Stale — a newer step selection happened while we were fetching
      if (gen != _initGeneration) return;

      _factors = results[0] as List<Factor>;

      final existingBindings = results[1] as ({
        Factor? x,
        Factor y,
        List<Factor> colFacets,
        List<Factor> rowFacets,
      })?;

      if (existingBindings != null) {
        _yBinding = existingBindings.y;
        _xBinding = existingBindings.x;
        _colFacetBindings.addAll(existingBindings.colFacets);
        _rowFacetBindings.addAll(existingBindings.rowFacets);
      }
    } catch (e) {
      // Stale — don't overwrite a newer step's state with this error
      if (gen != _initGeneration) return;
      _factorsError = 'Failed to load step: $e';
      _factors = [];
    }

    if (gen != _initGeneration) return;
    _isFactorsLoading = false;
    notifyListeners();
  }

  void setBinding(String role, Factor binding) {
    switch (role) {
      case 'x':
        _xBinding = binding;
      case 'y':
        _yBinding = binding;
    }
    resetViewport();
    notifyListeners();
  }

  void clearBinding(String role) {
    switch (role) {
      case 'x':
        _xBinding = null;
      case 'y':
        _yBinding = null;
    }
    resetViewport();
    notifyListeners();
  }

  /// Add a factor to a facet (appends to the list).
  void addFacet(String role, Factor binding) {
    switch (role) {
      case 'row_facet':
        _rowFacetBindings.add(binding);
      case 'col_facet':
        _colFacetBindings.add(binding);
    }
    resetViewport();
    notifyListeners();
  }

  /// Remove a specific factor from a facet by index.
  void removeFacet(String role, int index) {
    switch (role) {
      case 'row_facet':
        if (index < _rowFacetBindings.length) _rowFacetBindings.removeAt(index);
      case 'col_facet':
        if (index < _colFacetBindings.length) _colFacetBindings.removeAt(index);
    }
    resetViewport();
    notifyListeners();
  }

  void clearAll() {
    _xBinding = null;
    _yBinding = null;
    _rowFacetBindings.clear();
    _colFacetBindings.clear();
    resetViewport();
    notifyListeners();
  }

  // --- Viewport methods (no notifyListeners — viewport triggers direct re-render) ---

  bool get hasViewport =>
      _totalRowFacets > _windowRowCount || _totalColFacets > _windowColCount;

  int get viewportRowStart => _viewportRowStart;
  int get viewportColStart => _viewportColStart;
  int get viewportRowMin => _viewportRowStart;
  int get viewportRowMax =>
      (_viewportRowStart + _windowRowCount - 1).clamp(0, _totalRowFacets - 1);
  int get viewportColMin => _viewportColStart;
  int get viewportColMax =>
      (_viewportColStart + _windowColCount - 1).clamp(0, _totalColFacets - 1);
  int get windowRowCount => _windowRowCount;
  int get windowColCount => _windowColCount;
  int get totalRowFacets => _totalRowFacets;
  int get totalColFacets => _totalColFacets;

  void initViewport({
    required int totalRows,
    required int totalCols,
    required int windowRows,
    required int windowCols,
    int rowStart = 0,
    int colStart = 0,
  }) {
    _totalRowFacets = totalRows;
    _totalColFacets = totalCols;
    _windowRowCount = windowRows;
    _windowColCount = windowCols;
    _viewportRowStart = rowStart.clamp(0, (totalRows - windowRows).clamp(0, totalRows));
    _viewportColStart = colStart.clamp(0, (totalCols - windowCols).clamp(0, totalCols));
  }

  void updateCellDimensions(double cellHeight, double cellWidth) {
    _cellHeight = cellHeight;
    _cellWidth = cellWidth;
  }

  double? get committedXMin => _committedXMin;
  double? get committedXMax => _committedXMax;
  double? get committedYMin => _committedYMin;
  double? get committedYMax => _committedYMax;
  List<AxisMappingData> get committedMappings =>
      List.unmodifiable(_committedMappings);

  /// Store the committed axis state after a successful render.
  void setCommittedState({
    required List<AxisMappingData> mappings,
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
  }) {
    _committedMappings = mappings;
    _committedXMin = xMin;
    _committedXMax = xMax;
    _committedYMin = yMin;
    _committedYMax = yMax;
  }

  /// Compute a new ViewportFilter from an accumulated GPU transform.
  ///
  /// Maps screen bounds → committed pixel space → data space using the
  /// stored axis mappings from the last render.
  ///
  /// Returns null if no committed mappings exist.
  ViewportResult? computeNewViewport({
    required double scale,
    required double panX,
    required double panY,
    required double originX,
    required double originY,
    required double containerW,
    required double containerH,
  }) {
    if (_committedMappings.isEmpty) return null;

    // Combined translate
    final tx = originX * (1 - scale) + panX;
    final ty = originY * (1 - scale) + panY;

    // Visible area in committed-pixel space (invert the GPU transform)
    final visibleLeft = (0 - tx) / scale;
    final visibleRight = (containerW - tx) / scale;
    final visibleTop = (0 - ty) / scale;
    final visibleBottom = (containerH - ty) / scale;

    // Determine which facet panels are visible
    int? newRowStart;
    int? newColStart;
    int visibleRows = 0;
    int visibleCols = 0;
    double? newXMin, newXMax, newYMin, newYMax;

    if (_committedMappings.length == 1) {
      // Single panel — compute axis range narrowing
      visibleRows = 1;
      visibleCols = 1;
      final am = _committedMappings.first;
      if (am.pxRight > am.pxLeft) {
        newXMin = am.dataXMin +
            (visibleLeft - am.pxLeft) /
                (am.pxRight - am.pxLeft) *
                (am.dataXMax - am.dataXMin);
        newXMax = am.dataXMin +
            (visibleRight - am.pxLeft) /
                (am.pxRight - am.pxLeft) *
                (am.dataXMax - am.dataXMin);
      }
      if (am.pxBottom > am.pxTop) {
        // Y is inverted: pxTop = yMax, pxBottom = yMin in screen coords
        newYMax = am.dataYMax -
            (visibleTop - am.pxTop) /
                (am.pxBottom - am.pxTop) *
                (am.dataYMax - am.dataYMin);
        newYMin = am.dataYMax -
            (visibleBottom - am.pxTop) /
                (am.pxBottom - am.pxTop) *
                (am.dataYMax - am.dataYMin);
      }
    } else {
      // Multiple panels — compute viewport shift using cell dimensions.
      // Maintain current window size and slide the start position based
      // on how far the visible center has moved in cell units.
      if (_cellWidth > 0 && _cellHeight > 0) {
        // Center of the visible area in committed-pixel space
        final centerX = (visibleLeft + visibleRight) / 2;
        final centerY = (visibleTop + visibleBottom) / 2;

        // Find the top-left panel to use as reference origin
        double refLeft = double.infinity;
        double refTop = double.infinity;
        for (final am in _committedMappings) {
          if (am.pxLeft < refLeft) refLeft = am.pxLeft;
          if (am.pxTop < refTop) refTop = am.pxTop;
        }

        // Compute which cell the center falls in (relative to committed start)
        final colShift = ((centerX - refLeft) / _cellWidth).floor() -
            (_windowColCount ~/ 2);
        final rowShift = ((centerY - refTop) / _cellHeight).floor() -
            (_windowRowCount ~/ 2);

        newRowStart = (_viewportRowStart + rowShift)
            .clamp(0, (_totalRowFacets - _windowRowCount).clamp(0, _totalRowFacets));
        newColStart = (_viewportColStart + colShift)
            .clamp(0, (_totalColFacets - _windowColCount).clamp(0, _totalColFacets));
        visibleRows = _windowRowCount;
        visibleCols = _windowColCount;
      } else {
        // No cell dimensions available — fallback to overlap detection
        int minRow = _totalRowFacets;
        int maxRow = -1;
        int minCol = _totalColFacets;
        int maxCol = -1;

        for (final am in _committedMappings) {
          if (am.pxRight > visibleLeft &&
              am.pxLeft < visibleRight &&
              am.pxBottom > visibleTop &&
              am.pxTop < visibleBottom) {
            if (am.rowIdx < minRow) minRow = am.rowIdx;
            if (am.rowIdx > maxRow) maxRow = am.rowIdx;
            if (am.colIdx < minCol) minCol = am.colIdx;
            if (am.colIdx > maxCol) maxCol = am.colIdx;
          }
        }

        if (maxRow >= 0) {
          newRowStart = minRow;
          visibleRows = maxRow - minRow + 1;
          newColStart = minCol;
          visibleCols = maxCol - minCol + 1;
        }
      }
    }

    return ViewportResult(
      rowStart: newRowStart ?? _viewportRowStart,
      colStart: newColStart ?? _viewportColStart,
      windowRows: visibleRows > 0 ? visibleRows : _windowRowCount,
      windowCols: visibleCols > 0 ? visibleCols : _windowColCount,
      xMin: newXMin,
      xMax: newXMax,
      yMin: newYMin,
      yMax: newYMax,
    );
  }

  void resetViewport() {
    _viewportRowStart = 0;
    _viewportColStart = 0;
    _windowRowCount = 0;
    _windowColCount = 0;
    _totalRowFacets = 1;
    _totalColFacets = 1;
    _cellHeight = 0;
    _cellWidth = 0;
    _committedXMin = null;
    _committedXMax = null;
    _committedYMin = null;
    _committedYMax = null;
    _committedMappings = [];
  }

  void setGeomType(String type) {
    _geomType = type;
    notifyListeners();
  }

  void setPlotTheme(String theme) {
    _plotTheme = theme;
    notifyListeners();
  }
}

/// Per-panel axis mapping data extracted from viewport chrome.
/// Maps pixel bounds ↔ data ranges for a single facet panel.
class AxisMappingData {
  final int rowIdx;
  final int colIdx;
  final double pxLeft;
  final double pxRight;
  final double pxTop;
  final double pxBottom;
  final double dataXMin;
  final double dataXMax;
  final double dataYMin;
  final double dataYMax;

  const AxisMappingData({
    required this.rowIdx,
    required this.colIdx,
    required this.pxLeft,
    required this.pxRight,
    required this.pxTop,
    required this.pxBottom,
    required this.dataXMin,
    required this.dataXMax,
    required this.dataYMin,
    required this.dataYMax,
  });
}

/// Result of computeNewViewport — facet window + optional axis range overrides.
class ViewportResult {
  final int rowStart;
  final int colStart;
  final int windowRows;
  final int windowCols;
  final double? xMin;
  final double? xMax;
  final double? yMin;
  final double? yMax;

  const ViewportResult({
    required this.rowStart,
    required this.colStart,
    required this.windowRows,
    required this.windowCols,
    this.xMin,
    this.xMax,
    this.yMin,
    this.yMax,
  });

  bool get hasAxisOverrides =>
      xMin != null || xMax != null || yMin != null || yMax != null;
}
