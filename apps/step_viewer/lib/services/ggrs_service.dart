import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

import '../di/service_locator.dart';
import '../presentation/providers/plot_state_provider.dart';
import 'cube_query_service.dart';
import 'ggrs_interop.dart';

enum RenderPhase { idle, chrome, cubeQuery, streaming, complete }

/// 4-phase WASM render orchestrator.
///
/// Phase 1: Instant chrome (empty data → computeLayout → renderChrome)
/// Phase 2: CubeQuery lifecycle (Flutter/Dart SDK)
/// Phase 3: initPlotStream → getStreamLayout → renderChromeCanvas
/// Phase 4: loadAndMapChunk loop → renderDataPoints (progressive)
class GgrsService extends ChangeNotifier {
  GgrsService();

  static const int _chunkSize = 15000;

  int _renderGeneration = 0;
  RenderPhase _phase = RenderPhase.idle;
  String? _error;
  bool _wasmReady = false;
  bool _tercenInitialized = false;
  JSObject? _renderer;
  JSFunction? _textMeasurer;
  String? _serviceUri;
  String? _token;
  int _totalColFacets = 0;
  int _totalRowFacets = 0;

  // Stored params for viewport re-renders
  CubeQueryResult? _lastCqResult;
  String? _lastContainerId;
  double _lastWidth = 0;
  double _lastHeight = 0;
  bool _viewportHandlersAttached = false;

  RenderPhase get phase => _phase;
  String? get error => _error;
  bool get isRendering =>
      _phase != RenderPhase.idle && _phase != RenderPhase.complete;

  void setTercenCredentials(String serviceUri, String token) {
    _serviceUri = serviceUri;
    _token = token;
  }

  Future<void> render(
    String containerId,
    PlotStateProvider state,
    double width,
    double height,
  ) async {
    final gen = ++_renderGeneration;
    _phase = RenderPhase.chrome;
    _error = null;
    notifyListeners();

    try {
      // Debounce: collapse rapid state changes
      await Future.delayed(const Duration(milliseconds: 16));
      _checkGen(gen);
      await _ensureWasm(gen);

      final workflowId = state.workflowId;
      final stepId = state.stepId;
      final hasY = state.yBinding != null;

      // Phase 1: Instant chrome — only when no GPU content exists yet,
      // or when we need to show the empty state (no Y binding).
      // Skip when GPU content exists to avoid destroying the active renderer.
      final gpuAlreadyExists = _lastContainerId != null && hasY;
      if (!gpuAlreadyExists) {
        _renderBindingsChrome(containerId, state, width, height);
        _lastContainerId = null;
        _viewportHandlersAttached = false;
        await _yieldFrame(gen);
      }

      if (workflowId == null || stepId == null || !hasY) {
        _setPhase(gen, RenderPhase.complete);
        return;
      }

      // Phase 2: CubeQuery
      _setPhase(gen, RenderPhase.cubeQuery);
      final cqResult = await _runCubeQuery(gen, state);

      if (cqResult.nRows == 0) {
        _setPhase(gen, RenderPhase.complete);
        return;
      }

      // Store params for viewport re-renders
      _lastCqResult = cqResult;
      _lastContainerId = containerId;
      _lastWidth = width;
      _lastHeight = height;

      // Clear old split buffers on binding change
      if (gpuAlreadyExists) {
        GgrsInterop.clearAll(containerId);
      }

      // Phase 3: Stream init → skeleton → static chrome → viewport chrome → data
      _setPhase(gen, RenderPhase.streaming);

      // Compute viewport window sizes (fixed base cell size — zoom is GPU-based now)
      final windowRowCount = (height / 60).floor().clamp(1, 1 << 30);
      final windowColCount = (width / 100).floor().clamp(1, 1 << 30);

      // First init without viewport to get total facet counts
      final configJson = _buildInitConfig(cqResult, state);
      final metadata = await GgrsInterop.initPlotStream(_renderer!, configJson);
      _checkGen(gen);

      _totalColFacets = (metadata.getProperty<JSNumber>('total_col_facets'.toJS)).toDartInt;
      _totalRowFacets = (metadata.getProperty<JSNumber>('total_row_facets'.toJS)).toDartInt;

      // Store base axis ranges as initial committed ranges
      final baseYMin = (metadata.getProperty<JSNumber>('y_min'.toJS)).toDartDouble;
      final baseYMax = (metadata.getProperty<JSNumber>('y_max'.toJS)).toDartDouble;
      final baseXMin = (metadata.getProperty<JSNumber>('x_min'.toJS)).toDartDouble;
      final baseXMax = (metadata.getProperty<JSNumber>('x_max'.toJS)).toDartDouble;

      // Determine if viewport is needed
      final needsViewport = _totalRowFacets > windowRowCount ||
          _totalColFacets > windowColCount;

      String viewportJson = '';
      Map<String, dynamic>? viewportMap;
      if (needsViewport) {
        state.initViewport(
          totalRows: _totalRowFacets,
          totalCols: _totalColFacets,
          windowRows: windowRowCount,
          windowCols: windowColCount,
        );
        viewportMap = {
          'ri_min': state.viewportRowMin,
          'ri_max': state.viewportRowMax,
          'ci_min': state.viewportColMin,
          'ci_max': state.viewportColMax,
        };
        viewportJson = json.encode(viewportMap);

        // Re-init with viewport to scope WASM to visible cells
        final vpConfigJson = _buildInitConfig(cqResult, state,
            viewport: viewportMap);
        await GgrsInterop.initPlotStream(_renderer!, vpConfigJson);
        _checkGen(gen);
      }

      // Compute skeleton (caches PlotDimensions in WASM)
      GgrsInterop.computeSkeleton(
        _renderer!, width, height, viewportJson, _textMeasurer!,
      );

      // Static chrome: axes, ticks, column strips, title, labels (rendered once)
      final staticChrome = GgrsInterop.getStaticChrome(_renderer!);
      await GgrsInterop.renderStaticChrome(containerId, staticChrome);
      _checkGen(gen);

      // Viewport chrome: panels, grid, row strips, borders
      final vpChrome = GgrsInterop.getViewportChrome(
        _renderer!, viewportJson,
      );
      GgrsInterop.renderViewportChrome(containerId, vpChrome);

      // Extract cell dimensions + committed state from viewport chrome
      _extractCellDimensions(vpChrome, state);
      _storeCommittedState(vpChrome, state, baseXMin, baseXMax, baseYMin, baseYMax);

      await _yieldFrame(gen);

      // TODO(Phase 2): data streaming disabled — enable with tile cache
      debugPrint('[GgrsService] initial render data streaming disabled (Phase 1)');

      // Attach viewport handlers (always — zoom can create viewport from non-viewport)
      _attachViewportHandlers(state);

      _setPhase(gen, RenderPhase.complete);
    } on _CancelledException {
      // New render started — this one is stale
    } catch (e) {
      if (gen == _renderGeneration) {
        _error = 'Render failed: $e';
        _phase = RenderPhase.idle;
        debugPrint('GgrsService: $_error');
        notifyListeners();
      }
    }
  }

  Future<void> _ensureWasm(int gen) async {
    if (!_wasmReady) {
      await GgrsInterop.ensureWasmInitialized();
      _checkGen(gen);
      _wasmReady = true;
    }
    _renderer ??= GgrsInterop.createRenderer('ggrs-canvas');
    _textMeasurer ??= GgrsInterop.createTextMeasurer();
    if (!_tercenInitialized && _serviceUri != null && _token != null) {
      GgrsInterop.initializeTercen(_renderer!, _serviceUri!, _token!);
      _tercenInitialized = true;
    }
  }

  /// Phase 1: Render chrome with bindings only (no data).
  void _renderBindingsChrome(
    String containerId, PlotStateProvider state, double width, double height,
  ) {
    final payload = json.encode({
      'version': '1.0',
      'geom_type': state.geomType,
      'theme': state.plotTheme,
      'bindings': _buildBindingsMap(state),
      'qt_stream': {'data': <Map>[]},
      'column_stream': {'labels': <Map>[]},
      'row_stream': {'labels': <Map>[]},
    });
    final layoutInfo = GgrsInterop.computeLayout(
      _renderer!, payload, width, height, _textMeasurer!,
    );
    GgrsInterop.renderChrome(containerId, layoutInfo);
  }

  Future<CubeQueryResult> _runCubeQuery(int gen, PlotStateProvider state) async {
    final cubeQueryService = serviceLocator<CubeQueryService>();
    final result = await cubeQueryService.ensureCubeQuery(
      workflowId: state.workflowId!,
      stepId: state.stepId!,
      xColumn: state.xBinding?.name,
      yColumn: state.yBinding?.name,
      colFacetColumns:
          state.colFacetBindings.map((f) => f.name).toList(),
      rowFacetColumns:
          state.rowFacetBindings.map((f) => f.name).toList(),
    );
    _checkGen(gen);
    return result;
  }

  String _buildInitConfig(
    CubeQueryResult cqResult, PlotStateProvider state,
    {Map<String, dynamic>? viewport}
  ) {
    final xCol = state.xBinding?.name;
    final yCol = state.yBinding?.name;
    return json.encode({
      'tables': cqResult.tables,
      'bindings': {
        'x': xCol != null
            ? {'status': 'bound', 'column': xCol}
            : (yCol != null
                ? {'status': 'bound', 'column': '.obs'}
                : {'status': 'unbound'}),
        'y': yCol != null
            ? {'status': 'bound', 'column': yCol}
            : {'status': 'unbound'},
        'color': {'status': 'unbound'},
        'shape': {'status': 'unbound'},
        'size': {'status': 'unbound'},
        'col_facet': state.colFacetBindings.isNotEmpty
            ? {'status': 'bound', 'column': state.colFacetBindings.first.name}
            : {'status': 'unbound'},
        'row_facet': state.rowFacetBindings.isNotEmpty
            ? {'status': 'bound', 'column': state.rowFacetBindings.first.name}
            : {'status': 'unbound'},
      },
      'geom_type': state.geomType,
      'theme': state.plotTheme,
      if (yCol != null) 'y_label': yCol,
      if (xCol != null) 'x_label': xCol,
      if (viewport != null) 'viewport': viewport,
    });
  }

  /// Extract axis mappings from viewport chrome and store as committed state.
  void _storeCommittedState(
    JSObject vpChrome,
    PlotStateProvider state,
    double baseXMin,
    double baseXMax,
    double baseYMin,
    double baseYMax,
  ) {
    final mappings = _extractAxisMappings(vpChrome, state,
        baseXMin, baseXMax, baseYMin, baseYMax);
    state.setCommittedState(
      mappings: mappings,
      xMin: baseXMin,
      xMax: baseXMax,
      yMin: baseYMin,
      yMax: baseYMax,
    );
  }

  /// Extract per-panel axis mapping data from viewport chrome.
  ///
  /// Joins `panels` (PanelBounds — has explicit col_idx/row_idx) with
  /// `axis_mappings` (AxisMapping — has pixel bounds + data ranges) by
  /// array position (both arrays are parallel, built in the same cell loop).
  ///
  /// PanelBounds col_idx/row_idx are LOCAL (0-based within viewport window),
  /// so viewport offsets are added for global indices.
  List<AxisMappingData> _extractAxisMappings(
    JSObject vpChrome,
    PlotStateProvider state,
    double baseXMin,
    double baseXMax,
    double baseYMin,
    double baseYMax,
  ) {
    // Read panels (PanelBounds) — has col_idx, row_idx
    final panelsRaw = vpChrome.getProperty<JSAny?>('panels'.toJS);
    if (panelsRaw == null) return [];
    final panelBounds = (panelsRaw as JSArray).toDart;
    if (panelBounds.isEmpty) return [];

    // Read axis_mappings — parallel array, has pixel bounds + data ranges
    final axisMappingsRaw =
        vpChrome.getProperty<JSAny?>('axis_mappings'.toJS);
    List<JSAny?> axisMappings = [];
    if (axisMappingsRaw != null) {
      axisMappings = (axisMappingsRaw as JSArray).toDart;
    }

    // Viewport offsets for local → global index conversion
    final rowOffset = state.viewportRowStart;
    final colOffset = state.viewportColStart;

    final mappings = <AxisMappingData>[];
    for (var i = 0; i < panelBounds.length; i++) {
      final pb = panelBounds[i] as JSObject;

      // col_idx / row_idx from PanelBounds (local, 0-based within viewport)
      final localRowIdx =
          (pb.getProperty<JSNumber>('row_idx'.toJS)).toDartInt;
      final localColIdx =
          (pb.getProperty<JSNumber>('col_idx'.toJS)).toDartInt;

      // Pixel bounds + data ranges from axis_mappings (if available)
      double pxLeft, pxRight, pxTop, pxBottom;
      double dataXMin, dataXMax, dataYMin, dataYMax;

      if (i < axisMappings.length) {
        final am = axisMappings[i] as JSObject;
        pxLeft = (am.getProperty<JSNumber>('px_left'.toJS)).toDartDouble;
        pxRight = (am.getProperty<JSNumber>('px_right'.toJS)).toDartDouble;
        pxTop = (am.getProperty<JSNumber>('px_top'.toJS)).toDartDouble;
        pxBottom = (am.getProperty<JSNumber>('px_bottom'.toJS)).toDartDouble;
        dataXMin = (am.getProperty<JSNumber>('x_min'.toJS)).toDartDouble;
        dataXMax = (am.getProperty<JSNumber>('x_max'.toJS)).toDartDouble;
        dataYMin = (am.getProperty<JSNumber>('y_min'.toJS)).toDartDouble;
        dataYMax = (am.getProperty<JSNumber>('y_max'.toJS)).toDartDouble;
      } else {
        // Fallback: pixel bounds from PanelBounds, base data ranges
        pxLeft = (pb.getProperty<JSNumber>('x'.toJS)).toDartDouble;
        pxTop = (pb.getProperty<JSNumber>('y'.toJS)).toDartDouble;
        final w = (pb.getProperty<JSNumber>('width'.toJS)).toDartDouble;
        final h = (pb.getProperty<JSNumber>('height'.toJS)).toDartDouble;
        pxRight = pxLeft + w;
        pxBottom = pxTop + h;
        dataXMin = baseXMin;
        dataXMax = baseXMax;
        dataYMin = baseYMin;
        dataYMax = baseYMax;
      }

      mappings.add(AxisMappingData(
        rowIdx: localRowIdx + rowOffset,
        colIdx: localColIdx + colOffset,
        pxLeft: pxLeft,
        pxRight: pxRight,
        pxTop: pxTop,
        pxBottom: pxBottom,
        dataXMin: dataXMin,
        dataXMax: dataXMax,
        dataYMin: dataYMin,
        dataYMax: dataYMax,
      ));
    }
    return mappings;
  }

  /// Viewport-only re-render: skips Phase 1 (chrome skeleton) and Phase 2 (CubeQuery).
  /// Re-inits WASM with scoped viewport, rebuilds chrome, streams visible data.
  ///
  /// [axisRanges] — optional axis range overrides for axis zoom commits.
  Future<void> renderViewport(
    PlotStateProvider state, {
    double? xMin,
    double? xMax,
    double? yMin,
    double? yMax,
  }) async {
    if (_lastCqResult == null || _lastContainerId == null || _renderer == null) {
      debugPrint('[GgrsService] renderViewport: missing prerequisites, skipping');
      return;
    }

    final gen = ++_renderGeneration;
    debugPrint('[GgrsService] renderViewport START gen=$gen '
        'ri=${state.viewportRowMin}-${state.viewportRowMax} '
        'ci=${state.viewportColMin}-${state.viewportColMax}');
    _phase = RenderPhase.streaming;
    _error = null;
    notifyListeners();

    try {
      final containerId = _lastContainerId!;

      final viewportMap = <String, dynamic>{
        'ri_min': state.viewportRowMin,
        'ri_max': state.viewportRowMax,
        'ci_min': state.viewportColMin,
        'ci_max': state.viewportColMax,
        if (xMin != null) 'x_min': xMin,
        if (xMax != null) 'x_max': xMax,
        if (yMin != null) 'y_min': yMin,
        if (yMax != null) 'y_max': yMax,
      };

      // Re-init WASM with new viewport scope (data scoping)
      final configJson = _buildInitConfig(_lastCqResult!, state,
          viewport: viewportMap);
      final metadata = await GgrsInterop.initPlotStream(_renderer!, configJson);
      _checkGen(gen);
      debugPrint('[GgrsService] gen=$gen initPlotStream done');

      // Recompute skeleton (initPlotStream clears cached_dims)
      final viewportJson = json.encode(viewportMap);
      final skeletonViewportJson = state.hasViewport ? viewportJson : '';
      GgrsInterop.computeSkeleton(
        _renderer!, _lastWidth, _lastHeight, skeletonViewportJson, _textMeasurer!,
      );

      // If axis ranges changed, static chrome needs re-render (tick labels change)
      final hasAxisOverrides = xMin != null || xMax != null || yMin != null || yMax != null;
      if (hasAxisOverrides) {
        final staticChrome = GgrsInterop.getStaticChrome(_renderer!);
        await GgrsInterop.renderStaticChrome(containerId, staticChrome);
        _checkGen(gen);
      }

      // Replace viewport chrome (panels, grid, row strips, borders)
      final vpChrome = GgrsInterop.getViewportChrome(
        _renderer!, viewportJson,
      );
      // Reset GPU transform just before rendering new chrome — keeps old
      // zoomed visual during the async pipeline, then seamlessly swaps in
      // new content at identity transform.
      GgrsInterop.resetViewTransform(containerId);
      GgrsInterop.renderViewportChrome(containerId, vpChrome);
      _checkGen(gen);
      debugPrint('[GgrsService] gen=$gen renderViewportChrome done');

      _extractCellDimensions(vpChrome, state);

      // Update committed state from viewport chrome + metadata axis ranges
      final newXMin = (metadata.getProperty<JSNumber>('x_min'.toJS)).toDartDouble;
      final newXMax = (metadata.getProperty<JSNumber>('x_max'.toJS)).toDartDouble;
      final newYMin = (metadata.getProperty<JSNumber>('y_min'.toJS)).toDartDouble;
      final newYMax = (metadata.getProperty<JSNumber>('y_max'.toJS)).toDartDouble;
      _storeCommittedState(vpChrome, state, newXMin, newXMax, newYMin, newYMax);

      // TODO(Phase 2): data streaming disabled — enable with tile cache
      debugPrint('[GgrsService] gen=$gen data streaming disabled (Phase 1)');

      _setPhase(gen, RenderPhase.complete);
    } on _CancelledException {
      debugPrint('[GgrsService] gen=$gen CANCELLED');
    } catch (e) {
      debugPrint('[GgrsService] gen=$gen ERROR: $e');
      if (gen == _renderGeneration) {
        _error = 'Viewport render failed: $e';
        _phase = RenderPhase.idle;
        notifyListeners();
      }
    }
  }

  void _attachViewportHandlers(PlotStateProvider state) {
    if (_viewportHandlersAttached || _lastContainerId == null) return;
    _viewportHandlersAttached = true;

    GgrsInterop.attachViewportHandlers(
      _lastContainerId!,
      (double scale, double panX, double panY, double originX, double originY) {
        _handleCommit(scale, panX, panY, originX, originY, state);
      },
    );
  }

  /// Handle a commit from the GPU view transform.
  ///
  /// Maps the accumulated transform to a new ViewportFilter and re-renders.
  void _handleCommit(
    double scale,
    double panX,
    double panY,
    double originX,
    double originY,
    PlotStateProvider state,
  ) {
    if (_lastCqResult == null || _lastContainerId == null) return;

    debugPrint('[GgrsService] onCommit: scale=$scale pan=($panX,$panY) origin=($originX,$originY)');

    final vpResult = state.computeNewViewport(
      scale: scale,
      panX: panX,
      panY: panY,
      originX: originX,
      originY: originY,
      containerW: _lastWidth,
      containerH: _lastHeight,
    );

    if (vpResult == null) {
      // No committed mappings — reset transform and skip
      GgrsInterop.resetViewTransform(_lastContainerId!);
      return;
    }

    // Update facet window in state (including start positions)
    state.initViewport(
      totalRows: _totalRowFacets,
      totalCols: _totalColFacets,
      windowRows: vpResult.windowRows,
      windowCols: vpResult.windowCols,
      rowStart: vpResult.rowStart,
      colStart: vpResult.colStart,
    );

    if (vpResult.hasAxisOverrides && !state.hasViewport) {
      // Pure axis zoom on a single panel (or all facets visible) —
      // fast synchronous path, no initPlotStream needed.
      _commitAxisZoom(state, vpResult);
    } else if (state.hasViewport) {
      // Facet viewport change — full async path with initPlotStream.
      renderViewport(
        state,
        xMin: vpResult.xMin,
        xMax: vpResult.xMax,
        yMin: vpResult.yMin,
        yMax: vpResult.yMax,
      );
    } else {
      // All facets fit, no axis override — full re-render
      render(_lastContainerId!, state, _lastWidth, _lastHeight);
    }
  }

  /// Fast synchronous axis zoom commit.
  ///
  /// Skips initPlotStream (data unchanged) and computeSkeleton (layout unchanged).
  /// Only recomputes viewport chrome with narrowed axis ranges, then swaps it in.
  /// The cached PlotDimensions and PlotGenerator from the initial render are reused.
  void _commitAxisZoom(PlotStateProvider state, ViewportResult vpResult) {
    final containerId = _lastContainerId!;

    final viewportMap = <String, dynamic>{
      'ri_min': state.viewportRowMin,
      'ri_max': state.viewportRowMax,
      'ci_min': state.viewportColMin,
      'ci_max': state.viewportColMax,
      if (vpResult.xMin != null) 'x_min': vpResult.xMin,
      if (vpResult.xMax != null) 'x_max': vpResult.xMax,
      if (vpResult.yMin != null) 'y_min': vpResult.yMin,
      if (vpResult.yMax != null) 'y_max': vpResult.yMax,
    };
    final viewportJson = json.encode(viewportMap);

    debugPrint('[GgrsService] commitAxisZoom: $viewportJson');

    // Recompute viewport chrome with narrowed axis ranges (sync WASM call).
    // Reuses cached PlotDimensions + PlotGenerator — no network, no re-init.
    final vpChrome = GgrsInterop.getViewportChrome(_renderer!, viewportJson);

    // Reset GPU transform to identity, then immediately render new chrome.
    // The new chrome has narrowed ticks/grid matching the zoom level,
    // so resetting to identity produces the correct zoomed visual.
    GgrsInterop.resetViewTransform(containerId);
    GgrsInterop.renderViewportChrome(containerId, vpChrome);

    // Update committed state from viewport chrome
    _extractCellDimensions(vpChrome, state);

    // Use the axis overrides as the new committed base ranges (not initPlotStream metadata)
    final baseXMin = vpResult.xMin ?? state.committedXMin ?? 0;
    final baseXMax = vpResult.xMax ?? state.committedXMax ?? 1;
    final baseYMin = vpResult.yMin ?? state.committedYMin ?? 0;
    final baseYMax = vpResult.yMax ?? state.committedYMax ?? 1;
    _storeCommittedState(vpChrome, state, baseXMin, baseXMax, baseYMin, baseYMax);

    debugPrint('[GgrsService] commitAxisZoom done');
  }

  void _extractCellDimensions(JSObject layoutInfo, PlotStateProvider state) {
    final panels = layoutInfo.getProperty<JSAny?>('panel_backgrounds'.toJS);
    if (panels == null) return;
    final panelArray = panels as JSArray;
    if (panelArray.length == 0) return;

    final firstPanel = panelArray.toDart.first as JSObject;
    final cellWidth =
        (firstPanel.getProperty<JSNumber>('width'.toJS)).toDartDouble;
    final cellHeight =
        (firstPanel.getProperty<JSNumber>('height'.toJS)).toDartDouble;
    state.updateCellDimensions(cellHeight, cellWidth);
  }

  void _logPointDiagnostics(JSArray points, int chunkIdx) {
    final dartPoints = points.toDart;
    final count = dartPoints.length.clamp(0, 3);
    for (var i = 0; i < count; i++) {
      final pt = dartPoints[i] as JSObject;
      final px = (pt.getProperty<JSNumber>('px'.toJS)).toDartDouble;
      final py = (pt.getProperty<JSNumber>('py'.toJS)).toDartDouble;
      debugPrint('[DIAG]   chunk$chunkIdx point[$i]: px=$px py=$py');
    }
  }

  void _checkGen(int gen) {
    if (gen != _renderGeneration) throw _CancelledException();
  }

  Future<void> _yieldFrame(int gen) async {
    await GgrsInterop.yieldFrame();
    _checkGen(gen);
  }

  void _setPhase(int gen, RenderPhase phase) {
    _checkGen(gen);
    _phase = phase;
    notifyListeners();
  }

  Map<String, dynamic> _buildBindingsMap(PlotStateProvider state) {
    return {
      'x': state.xBinding != null
          ? {'status': 'bound', 'column': state.xBinding!.name}
          : {'status': 'unbound'},
      'y': state.yBinding != null
          ? {'status': 'bound', 'column': state.yBinding!.name}
          : {'status': 'unbound'},
      'color': {'status': 'unbound'},
      'shape': {'status': 'unbound'},
      'size': {'status': 'unbound'},
      'row_facet': state.rowFacetBindings.isNotEmpty
          ? {'status': 'bound', 'column': state.rowFacetBindings.first.name}
          : {'status': 'unbound'},
      'col_facet': state.colFacetBindings.isNotEmpty
          ? {'status': 'bound', 'column': state.colFacetBindings.first.name}
          : {'status': 'unbound'},
    };
  }
}

class _CancelledException implements Exception {}
