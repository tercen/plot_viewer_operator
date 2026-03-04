import 'dart:js_interop';
import 'package:flutter/foundation.dart';

import '../presentation/providers/plot_state_provider.dart';
import 'ggrs_interop_v3.dart';
import 'ggrs_service_v2.dart' show RenderPhase;

/// V3 render service — Mock viewport-driven rendering (test_streaming.html behavior in Dart).
///
/// Flow:
///   1. Ensure WASM loaded
///   2. Ensure GPU created (creates ViewportState + InteractionManager)
///   3. Configure viewport with mock 10x10 grid
///   4. Stream mock data (50K points)
///
/// Zoom, scroll, chrome are all handled in JS by ViewportState + InteractionManager.
/// Dart's only job: init pipeline, configure grid dimensions, trigger data streaming.
class GgrsServiceV3 extends ChangeNotifier {
  GgrsServiceV3();

  int _renderGeneration = 0;
  RenderPhase _phase = RenderPhase.idle;
  String? _error;
  bool _wasmReady = false;
  JSObject? _renderer;

  /// Track active containers
  final Set<String> _activeContainers = {};
  String? _activeContainerId;

  RenderPhase get phase => _phase;
  String? get error => _error;
  String? get activeContainerId => _activeContainerId;
  bool get isRendering => _renderGeneration > 0;

  /// Set Tercen credentials (no-op in mock mode, kept for interface compatibility).
  void setTercenCredentials(String serviceUri, String token) {
    // Not used in mock mode
  }

  Future<void> render(
    String containerId,
    PlotStateProvider state,
    double width,
    double height,
  ) async {
    final gen = ++_renderGeneration;
    _activeContainerId = containerId;
    _phase = RenderPhase.chrome;
    _error = null;
    notifyListeners();

    try {
      final sw = Stopwatch()..start();
      void log(String msg) =>
          debugPrint('[GgrsV3] $msg @ ${sw.elapsedMilliseconds}ms');

      // Debounce rapid changes
      await Future.delayed(const Duration(milliseconds: 16));
      _checkGen(gen);

      // ── 1. Ensure WASM + GPU ───────────────────────────────────────────────

      await _ensureWasm(gen);
      log('WASM ready');

      await GgrsInteropV3.ensureGpu(
        containerId,
        width.toInt(),
        height.toInt(),
        _renderer!,
      );
      _checkGen(gen);
      _activeContainers.add(containerId);
      log('GPU + ViewportState + InteractionManager ready');

      // ── 2. Initialize mock plot stream and get metadata ────────────────────

      log('Mock mode: initializing 10x10 grid with 50K points');

      _phase = RenderPhase.chrome;
      notifyListeners();

      final metadata = await GgrsInteropV3.initMockPlotStream(_renderer!, {
        'n_col_facets': 10,
        'n_row_facets': 10,
        'total_rows': 500000,
        'x_min': 0.0,
        'x_max': 100.0,
        'y_min': 0.0,
        'y_max': 100.0,
      });
      _checkGen(gen);

      log('Mock metadata received: ${metadata.keys.join(", ")}');

      // Build PlotState metadata structure from WASM result
      final plotMetadata = {
        'grid': {
          'totalCols': metadata['n_col_facets'],
          'totalRows': metadata['n_row_facets'],
        },
        'axes': {
          'xMin': metadata['x_min'],
          'xMax': metadata['x_max'],
          'yMin': metadata['y_min'],
          'yMax': metadata['y_max'],
        },
        'data': {
          'nRows': metadata['n_rows'],
        },
        'dataInsets': {
          'left': metadata['data_inset_left'],
          'top': metadata['data_inset_top'],
          'right': metadata['data_inset_right'],
          'bottom': metadata['data_inset_bottom'],
        },
      };

      // Pass metadata to PlotState
      GgrsInteropV3.setPlotMetadata(containerId, plotMetadata);

      // Initial chrome (layout sync handled by continuous render loop)
      GgrsInteropV3.renderChrome(containerId);
      _checkGen(gen);

      // ── 3. Stream mock data with viewport filter ───────────────────────────

      _phase = RenderPhase.streaming;
      notifyListeners();

      // Calculate viewport-based facet filter (show first 6x6 facets of 10x10 grid)
      // This simulates a viewport showing ~36 panels with room for scroll buffer
      final totalCols = metadata['n_col_facets'] as int;
      final totalRows = metadata['n_row_facets'] as int;
      final viewportCols = (totalCols * 0.6).ceil(); // 60% of columns
      final viewportRows = (totalRows * 0.6).ceil(); // 60% of rows

      final facetFilter = {
        'facet': {
          'col_range': [0, viewportCols],
          'row_range': [0, viewportRows],
        },
        'spatial': {
          'x_column': 'x',
          'x_min': null,
          'x_max': null,
          'y_column': 'y',
          'y_min': null,
          'y_max': null,
        },
      };

      log('Streaming mock data with viewport filter: ${viewportCols}x${viewportRows} facets (of ${totalCols}x${totalRows})');

      await GgrsInteropV3.streamMockData(
        containerId,
        chunkSize: 5000,
        facet_filter: facetFilter,
      );
      _checkGen(gen);

      _renderGeneration = 0;
      _phase = RenderPhase.complete;
      notifyListeners();
      log('Mock render complete');
    } catch (e, stack) {
      if (_renderGeneration == gen) {
        _error = e.toString();
        _renderGeneration = 0;
        _phase = RenderPhase.idle;
        notifyListeners();
        debugPrint('[GgrsV3] Error: $e');
        debugPrint('[GgrsV3] Stack: $stack');
      }
    }
  }

  /// Load additional facets in background (triggered by viewport scroll/zoom).
  ///
  /// Implements sliding window: loads NEW facet rectangles and appends to
  /// existing kept points (overlap was already filtered in JS).
  ///
  /// [loadId] is the history snapshot ID from PlotState, used to correctly
  /// place data even if viewport has changed during async load.
  Future<void> loadFacetsInBackground(
    String containerId,
    List<dynamic> newRectangles,
    Map<String, dynamic> neededRange,
    int loadId,
  ) async {
    try {
      debugPrint('[GgrsV3] ========== loadFacetsInBackground START ==========');
      debugPrint('[GgrsV3] containerId: $containerId');
      debugPrint('[GgrsV3] newRectangles.length: ${newRectangles.length}');
      debugPrint('[GgrsV3] neededRange: $neededRange');
      debugPrint('[GgrsV3] _renderer: ${_renderer != null ? "available" : "NULL"}');

      final allNewPoints = <Map<String, dynamic>>[];

      // Load each new rectangle using the stateless loadFacetRectangle API
      for (var i = 0; i < newRectangles.length; i++) {
        final rect = newRectangles[i];
        final rectMap = rect as Map<String, dynamic>;
        final colStart = rectMap['colStart'] as int;
        final colEnd = rectMap['colEnd'] as int;
        final rowStart = rectMap['rowStart'] as int;
        final rowEnd = rectMap['rowEnd'] as int;

        debugPrint('[GgrsV3] Loading rect ${i + 1}/${newRectangles.length}: cols [$colStart, $colEnd), rows [$rowStart, $rowEnd)');

        debugPrint('[GgrsV3]   Calling loadFacetRectangle...');
        // Load data for this rectangle using the new stateless API
        final points = await GgrsInteropV3.loadFacetRectangle(
          _renderer!,
          colStart,
          colEnd,
          rowStart,
          rowEnd,
        );

        debugPrint('[GgrsV3]   → Loaded ${points.length} points for rect ${i + 1}');
        allNewPoints.addAll(points);
      }

      debugPrint('[GgrsV3] All rectangles loaded: ${allNewPoints.length} total new points');
      debugPrint('[GgrsV3] Calling appendDataPoints (load #$loadId)...');

      // Append to GPU via JavaScript (merges with kept overlap points)
      // Pass loadId so JS can retrieve historical viewport state for correct placement
      GgrsInteropV3.appendDataPoints(containerId, allNewPoints, neededRange, loadId);

      debugPrint('[GgrsV3] ========== loadFacetsInBackground COMPLETE ==========');
    } catch (e, stack) {
      debugPrint('[GgrsV3] ⚠️ Background load ERROR: $e');
      debugPrint('[GgrsV3] Stack: $stack');
    }
  }

  void _checkGen(int gen) {
    if (gen != _renderGeneration) {
      throw Exception('Render cancelled (stale generation)');
    }
  }

  Future<void> _ensureWasm(int gen) async {
    if (_wasmReady) return;

    // Load WASM module
    await GgrsInteropV3.loadWasm();
    _checkGen(gen);

    // Create renderer (needed for mock data generator)
    final containerId = _activeContainerId ?? 'plot-container';
    _renderer = GgrsInteropV3.createRenderer(containerId);
    _checkGen(gen);

    _wasmReady = true;
  }

  @override
  void dispose() {
    for (final containerId in _activeContainers) {
      GgrsInteropV3.cleanup(containerId);
    }
    _activeContainers.clear();
    super.dispose();
  }
}
