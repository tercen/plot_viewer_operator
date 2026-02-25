import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

import '../di/service_locator.dart';
import '../presentation/providers/plot_state_provider.dart';
import 'cube_query_service.dart';
import 'ggrs_interop_v2.dart';

enum RenderPhase { idle, chrome, cubeQuery, streaming, complete }

/// V2 render orchestrator — data-space GPU rendering.
///
/// Two-concern architecture:
///   1. Viewport manipulation (JS-only, instant) — zoom, pan, facet scroll
///   2. Completeness detector (async) — chrome staleness, data gaps
///
/// Render phases (heavy path, runs on binding change):
///   - CubeQuery lifecycle (Flutter/Dart SDK)
///   - initPlotStream → skeleton → ensureGpu → chrome → panel layout
///   - loadDataChunk loop → appendDataPoints (progressive)
///
/// Phase 1 SVG chrome only renders when no GPU is active (empty/no-data state).
class GgrsServiceV2 extends ChangeNotifier {
  GgrsServiceV2();

  static const int _chunkSize = 15000;
  static const int _facetRowBuffer = 2;

  int _renderGeneration = 0;
  RenderPhase _phase = RenderPhase.idle;
  String? _error;
  bool _wasmReady = false;
  bool _tercenInitialized = false;
  JSObject? _renderer;
  JSFunction? _textMeasurer;
  String? _serviceUri;
  String? _token;

  /// Track which containers have an active GPU — keyed by containerId.
  final Set<String> _gpuReady = {};

  RenderPhase get phase => _phase;
  String? get error => _error;
  bool get isRendering =>
      _phase != RenderPhase.idle && _phase != RenderPhase.complete;

  bool _isGpuReady(String containerId) => _gpuReady.contains(containerId);

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

    // Cancel any in-flight JS streaming loop before doing anything
    GgrsInteropV2.cancelStreaming(containerId);

    try {
      // Debounce: collapse rapid state changes
      await Future.delayed(const Duration(milliseconds: 16));
      _checkGen(gen);
      await _ensureWasm(gen);

      final workflowId = state.workflowId;
      final stepId = state.stepId;
      final hasY = state.yBinding != null;

      // Early exit: no Y binding → empty state chrome only
      if (workflowId == null || stepId == null || !hasY) {
        if (!_isGpuReady(containerId)) {
          _renderBindingsChrome(containerId, state, width, height);
        }
        _setPhase(gen, RenderPhase.complete);
        return;
      }

      // Phase 1: Instant chrome (only when no GPU yet)
      if (!_isGpuReady(containerId)) {
        _renderBindingsChrome(containerId, state, width, height);
        await GgrsInteropV2.yieldFrame();
        _checkGen(gen);
      }

      // CubeQuery
      _setPhase(gen, RenderPhase.cubeQuery);
      final cqResult = await _runCubeQuery(gen, state);

      if (cqResult.nRows == 0) {
        _setPhase(gen, RenderPhase.complete);
        return;
      }

      // Stream init
      _setPhase(gen, RenderPhase.streaming);

      final configJson = _buildInitConfig(cqResult, state);
      final metadata =
          await GgrsInteropV2.initPlotStream(_renderer!, configJson);
      _checkGen(gen);

      final nColFacets =
          (metadata.getProperty<JSNumber>('n_col_facets'.toJS)).toDartInt;
      final nRowFacets =
          (metadata.getProperty<JSNumber>('n_row_facets'.toJS)).toDartInt;
      final xMin =
          (metadata.getProperty<JSNumber>('x_min'.toJS)).toDartDouble;
      final xMax =
          (metadata.getProperty<JSNumber>('x_max'.toJS)).toDartDouble;
      final yMin =
          (metadata.getProperty<JSNumber>('y_min'.toJS)).toDartDouble;
      final yMax =
          (metadata.getProperty<JSNumber>('y_max'.toJS)).toDartDouble;

      // Ensure GPU (creates once, resizes on subsequent calls)
      await GgrsInteropV2.ensureGpu(containerId, width, height);
      _gpuReady.add(containerId);
      _checkGen(gen);

      // Compute skeleton for panel dimensions (sync WASM call)
      final skeleton = GgrsInteropV2.computeSkeleton(
        _renderer!, width, height, '', _textMeasurer!,
      );

      // Parse panel grid from skeleton
      final panelGrid =
          skeleton.getProperty<JSObject>('panel_grid'.toJS);
      final cellWidth =
          (panelGrid.getProperty<JSNumber>('cell_width'.toJS)).toDartDouble;
      final cellHeight =
          (panelGrid.getProperty<JSNumber>('cell_height'.toJS)).toDartDouble;
      final cellSpacing =
          (panelGrid.getProperty<JSNumber>('cell_spacing'.toJS)).toDartDouble;
      final offsetX =
          (panelGrid.getProperty<JSNumber>('offset_x'.toJS)).toDartDouble;
      final offsetY =
          (panelGrid.getProperty<JSNumber>('offset_y'.toJS)).toDartDouble;

      // Chrome (WASM skeleton → merge in JS → GPU rects + text canvas)
      final staticChrome = GgrsInteropV2.getStaticChrome(_renderer!);
      final vpChrome = GgrsInteropV2.getViewportChrome(_renderer!, '');
      GgrsInteropV2.mergeAndSetChrome(containerId, staticChrome, vpChrome);

      // Panel layout → view uniforms (80 bytes)
      // n_visible_rows includes buffer for smooth scrolling
      final nVisibleRows = nRowFacets + _facetRowBuffer;
      final panelParams = <String, Object>{
        'xMin': xMin,
        'xMax': xMax,
        'yMin': yMin,
        'yMax': yMax,
        'gridOriginX': offsetX,
        'gridOriginY': offsetY,
        'cellWidth': cellWidth,
        'cellHeight': cellHeight,
        'cellSpacing': cellSpacing,
        'nVisibleCols': nColFacets,
        'nVisibleRows': nVisibleRows,
        'nActualCols': nColFacets,
        'nActualRows': nRowFacets,
        'vpColStart': 0,
        'vpRowStart': 0,
      };
      GgrsInteropV2.setPanelLayout(
          containerId, _toJSObject(panelParams));

      // Interaction (attaches once, updates chrome refs on re-render)
      GgrsInteropV2.attachInteraction(
          containerId, _renderer!, staticChrome, vpChrome);

      await GgrsInteropV2.yieldFrame();
      _checkGen(gen);

      // DATA STREAMING DISABLED — focusing on chrome/viewport first
      // final options = _toJSObject(<String, Object>{
      //   'radius': 2.5,
      //   'fillColor': 'rgba(0,0,0,0.6)',
      // });
      // await GgrsInteropV2.streamAllData(
      //     containerId, _renderer!, _chunkSize, options);
      // _checkGen(gen);

      _setPhase(gen, RenderPhase.complete);
    } on _CancelledException {
      // New render started — this one is stale
    } catch (e) {
      if (gen == _renderGeneration) {
        _error = 'Render failed: $e';
        _phase = RenderPhase.idle;
        debugPrint('GgrsServiceV2: $_error');
        notifyListeners();
      }
    }
  }

  Future<void> _ensureWasm(int gen) async {
    if (!_wasmReady) {
      await GgrsInteropV2.ensureWasmInitialized();
      _checkGen(gen);
      _wasmReady = true;
    }
    _renderer ??= GgrsInteropV2.createRenderer('ggrs-canvas');
    _textMeasurer ??= GgrsInteropV2.createTextMeasurer();
    if (!_tercenInitialized && _serviceUri != null && _token != null) {
      GgrsInteropV2.initializeTercen(_renderer!, _serviceUri!, _token!);
      _tercenInitialized = true;
    }
  }

  /// Phase 1: Render chrome with bindings only (no data).
  /// Only called when no GPU is active for this container.
  void _renderBindingsChrome(
    String containerId,
    PlotStateProvider state,
    double width,
    double height,
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
    final layoutInfo = GgrsInteropV2.computeLayout(
      _renderer!, payload, width, height, _textMeasurer!,
    );
    GgrsInteropV2.renderChrome(containerId, layoutInfo);
  }

  Future<CubeQueryResult> _runCubeQuery(
      int gen, PlotStateProvider state) async {
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
      CubeQueryResult cqResult, PlotStateProvider state) {
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
            ? {
                'status': 'bound',
                'column': state.colFacetBindings.first.name,
              }
            : {'status': 'unbound'},
        'row_facet': state.rowFacetBindings.isNotEmpty
            ? {
                'status': 'bound',
                'column': state.rowFacetBindings.first.name,
              }
            : {'status': 'unbound'},
      },
      'geom_type': state.geomType,
      'theme': state.plotTheme,
      if (yCol != null) 'y_label': yCol,
      if (xCol != null) 'x_label': xCol,
    });
  }

  JSObject _toJSObject(Map<String, Object> map) {
    final jsonObj = globalContext.getProperty<JSObject>('JSON'.toJS);
    return jsonObj.callMethod<JSObject>('parse'.toJS, json.encode(map).toJS);
  }

  void _checkGen(int gen) {
    if (gen != _renderGeneration) throw _CancelledException();
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
          ? {
              'status': 'bound',
              'column': state.rowFacetBindings.first.name,
            }
          : {'status': 'unbound'},
      'col_facet': state.colFacetBindings.isNotEmpty
          ? {
              'status': 'bound',
              'column': state.colFacetBindings.first.name,
            }
          : {'status': 'unbound'},
    };
  }
}

class _CancelledException implements Exception {}
