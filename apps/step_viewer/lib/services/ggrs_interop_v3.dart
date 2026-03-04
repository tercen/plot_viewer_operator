import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Dart↔JS interop for GGRS v3 architecture (viewport-driven).
///
/// This layer provides type-safe access to:
/// - WASM GGRSRenderer (Rust compiled to WebAssembly)
/// - Bootstrap v3 functions (JavaScript GPU/viewport/interaction management)
///
/// API matches the simplified bootstrap_v3.js exports:
/// - ensureWasm / createRenderer / initializeTercen
/// - ensureGpu / setViewportConfig / renderChrome
/// - streamMockData / streamData / appendDataPoints
/// - ensureCubeQuery / initPlotStream (Phase 2)
///
/// Note: Layout sync happens automatically via continuous 60fps render loop,
/// no manual syncLayout() needed.
class GgrsInteropV3 {
  /// Load WASM module.
  static Future<void> loadWasm() async {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final initFn = bootstrapModule['ensureWasmInitialized'] as JSFunction;
    final promise = initFn.callAsFunction(null) as JSPromise;
    await promise.toDart;
  }

  /// Create a WASM renderer instance.
  static JSObject createRenderer(String containerId) {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final createFn = bootstrapModule['createRenderer'] as JSFunction;
    return createFn.callAsFunction(null, containerId.toJS) as JSObject;
  }

  /// Initialize Tercen HTTP client in WASM.
  static void initializeTercen(
    JSObject renderer,
    String serviceUri,
    String token,
  ) {
    renderer.callMethod(
      'initializeTercen'.toJS,
      serviceUri.toJS,
      token.toJS,
    );
  }

  /// Ensure GPU + ViewportState + InteractionManager for a container.
  static Future<void> ensureGpu(
    String containerId,
    int width,
    int height,
    JSObject renderer,
  ) async {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final ensureGpuFn = bootstrapModule['ggrsV3EnsureGpu'] as JSFunction;
    final promise = ensureGpuFn.callAsFunction(
      null,
      containerId.toJS,
      width.toJS,
      height.toJS,
      renderer,
    ) as JSPromise;
    await promise.toDart;
  }

  /// Initialize mock plot stream and return metadata (Phase 1).
  static Future<Map<String, dynamic>> initMockPlotStream(
    JSObject renderer,
    Map<String, dynamic> config,
  ) async {
    final jsConfig = JSObject();
    config.forEach((key, value) {
      if (value is int) {
        jsConfig.setProperty(key.toJS, value.toJS);
      } else if (value is double) {
        jsConfig.setProperty(key.toJS, value.toJS);
      } else if (value is String) {
        jsConfig.setProperty(key.toJS, value.toJS);
      }
    });

    // JSON.stringify(jsConfig)
    final json = globalContext['JSON'] as JSObject;
    final stringifyFn = json['stringify'] as JSFunction;
    final configJson = stringifyFn.callAsFunction(json, jsConfig) as JSString;

    final resultJson = renderer.callMethod(
      'initMockPlotStream'.toJS,
      configJson,
    ) as JSString;

    // JSON.parse(resultJson)
    final parseFn = json['parse'] as JSFunction;
    final resultObj = parseFn.callAsFunction(json, resultJson) as JSObject;

    // Object.keys(resultObj)
    final objectConstructor = globalContext['Object'] as JSObject;
    final keysFn = objectConstructor['keys'] as JSFunction;
    final keys = keysFn.callAsFunction(objectConstructor, resultObj) as JSArray;

    // Convert JSObject to Dart Map
    final result = <String, dynamic>{};
    for (int i = 0; i < keys.length.toInt(); i++) {
      final key = (keys[i] as JSString).toDart;
      final value = resultObj.getProperty(key.toJS);

      if (value is JSNumber) {
        result[key] = value.toDartDouble;
      } else if (value is JSString) {
        result[key] = value.toDart;
      } else if (value is JSBoolean) {
        result[key] = value.toDart;
      }
    }

    return result;
  }

  /// Set plot metadata from WASM initPlotStream result (Phase 2).
  static void setPlotMetadata(String containerId, Map<String, dynamic> metadata) {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final fn = bootstrapModule['ggrsV3SetPlotMetadata'] as JSFunction;

    final jsMetadata = JSObject();
    metadata.forEach((key, value) {
      if (value is Map) {
        final nested = JSObject();
        (value as Map<String, dynamic>).forEach((k, v) {
          if (v is int) {
            nested.setProperty(k.toJS, v.toJS);
          } else if (v is double) {
            nested.setProperty(k.toJS, v.toJS);
          } else if (v is String) {
            nested.setProperty(k.toJS, v.toJS);
          } else if (v is List) {
            // Convert List to JSArray
            final jsArray = v.map((item) {
              if (item is String) return item.toJS;
              if (item is int) return item.toJS;
              if (item is double) return item.toJS;
              return item.toString().toJS;
            }).toList().toJS;
            nested.setProperty(k.toJS, jsArray);
          }
        });
        jsMetadata.setProperty(key.toJS, nested);
      } else if (value is int) {
        jsMetadata.setProperty(key.toJS, value.toJS);
      } else if (value is double) {
        jsMetadata.setProperty(key.toJS, value.toJS);
      } else if (value is String) {
        jsMetadata.setProperty(key.toJS, value.toJS);
      }
    });

    fn.callAsFunction(null, containerId.toJS, jsMetadata);
  }

  /// Configure viewport with grid dimensions and axis ranges.
  static void setViewportConfig(String containerId, Map<String, dynamic> config) {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final fn = bootstrapModule['ggrsV3SetViewportConfig'] as JSFunction;

    final jsConfig = JSObject();
    config.forEach((key, value) {
      if (value is int) {
        jsConfig.setProperty(key.toJS, value.toJS);
      } else if (value is double) {
        jsConfig.setProperty(key.toJS, value.toJS);
      } else if (value is String) {
        jsConfig.setProperty(key.toJS, value.toJS);
      }
    });

    fn.callAsFunction(null, containerId.toJS, jsConfig);
  }

  /// Render chrome from ViewportState to GPU layers.
  static void renderChrome(String containerId) {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final fn = bootstrapModule['ggrsV3RenderChrome'] as JSFunction;
    fn.callAsFunction(null, containerId.toJS);
  }

  /// Stream mock data from WASM MockStreamGenerator (Phase 1 testing).
  ///
  /// [facet_filter] is optional DataFilter for viewport-aware loading:
  /// {
  ///   "facet": { "col_range": [0, 5], "row_range": [0, 5] },
  ///   "spatial": { "x_column": "x", "x_min": null, "x_max": null, "y_column": "y", "y_min": null, "y_max": null }
  /// }
  /// Pass null for full data (all facets).
  static Future<void> streamMockData(
    String containerId, {
    int chunkSize = 5000,
    Map<String, dynamic>? facet_filter,
  }) async {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final fn = bootstrapModule['ggrsV3StreamMockData'] as JSFunction;

    final jsOpts = JSObject();
    jsOpts.setProperty('chunkSize'.toJS, chunkSize.toJS);
    if (facet_filter != null) {
      jsOpts.setProperty('facet_filter'.toJS, facet_filter.jsify());
    }

    final promise =
        fn.callAsFunction(null, containerId.toJS, jsOpts) as JSPromise;
    await promise.toDart;
  }

  /// Stream real data from WASM (Phase 2).
  ///
  /// [facet_filter] is optional DataFilter for viewport-aware loading and PNG export:
  /// {
  ///   "facet": { "col_range": [0, 5], "row_range": [0, 5] },
  ///   "spatial": { "x_column": "x", "x_min": 25.0, "x_max": 75.0, "y_column": "y", "y_min": null, "y_max": null }
  /// }
  /// Pass null for full data (e.g., PNG export with all facets).
  static Future<void> streamData(
    String containerId, {
    int chunkSize = 15000,
    Map<String, dynamic>? facet_filter,
  }) async {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final fn = bootstrapModule['ggrsV3StreamData'] as JSFunction;

    final promise = fn.callAsFunction(
      null,
      containerId.toJS,
      chunkSize.toJS,
      facet_filter?.jsify(),
    ) as JSPromise;
    await promise.toDart;
  }

  /// Load a specific facet rectangle (stateless, for sliding window).
  ///
  /// This calls the new WASM loadFacetRectangle API which is stateless and
  /// returns ALL points for the specified facet rectangle in one call.
  /// Each call is independent - perfect for loading disconnected rectangles.
  ///
  /// Used for background facet loading triggered by viewport scroll/zoom.
  static Future<List<Map<String, dynamic>>> loadFacetRectangle(
    JSObject renderer,
    int colStart,
    int colEnd,
    int rowStart,
    int rowEnd,
  ) async {
    final resultJson = await (renderer.callMethod(
      'loadFacetRectangle'.toJS,
      colStart.toJS,
      colEnd.toJS,
      rowStart.toJS,
      rowEnd.toJS,
    ) as JSPromise)
        .toDart as JSString;

    final json = globalContext['JSON'] as JSObject;
    final parseFn = json['parse'] as JSFunction;
    final pointsArray = parseFn.callAsFunction(json, resultJson) as JSArray;

    final points = <Map<String, dynamic>>[];
    for (var i = 0; i < pointsArray.length; i++) {
      final point = pointsArray[i] as JSObject;
      points.add({
        'x': (point['x'] as JSNumber).toDartDouble,
        'y': (point['y'] as JSNumber).toDartDouble,
        'ci': (point['ci'] as JSNumber).toDartInt,
        'ri': (point['ri'] as JSNumber).toDartInt,
      });
    }

    return points;
  }

  /// Stream mock data in background and return points (for incremental loading).
  ///
  /// DEPRECATED: Use loadFacetRectangle instead for disconnected rectangle loading.
  /// This uses the continuous streaming API which has issues with loaded_rows counter.
  ///
  /// Unlike streamMockData, this collects and returns the points instead of
  /// directly updating GPU. Used for background facet loading triggered by
  /// viewport scroll/zoom.
  static Future<List<Map<String, dynamic>>> streamMockDataBackground(
    String containerId,
    JSObject renderer, {
    int chunkSize = 5000,
    Map<String, dynamic>? facet_filter,
  }) async {
    final allPoints = <Map<String, dynamic>>[];
    bool done = false;

    final filterJson = facet_filter != null
        ? (globalContext['JSON'] as JSObject)
            .callMethod('stringify'.toJS, facet_filter.jsify())
            .toString()
        : null;

    while (!done) {
      final resultJson = await (renderer.callMethod(
        'loadDataChunk'.toJS,
        chunkSize.toJS,
        filterJson?.toJS,
      ) as JSPromise)
          .toDart as JSString;

      final json = globalContext['JSON'] as JSObject;
      final parseFn = json['parse'] as JSFunction;
      final resultObj = parseFn.callAsFunction(json, resultJson) as JSObject;

      final pointsArray = resultObj['points'] as JSArray?;
      if (pointsArray != null) {
        final length = (resultObj['points'] as JSArray).length;
        for (var i = 0; i < length; i++) {
          final point = pointsArray[i] as JSObject;
          allPoints.add({
            'x': (point['x'] as JSNumber).toDartDouble,
            'y': (point['y'] as JSNumber).toDartDouble,
            'ci': (point['ci'] as JSNumber).toDartInt,
            'ri': (point['ri'] as JSNumber).toDartInt,
          });
        }
      }

      done = (resultObj['done'] as JSBoolean).toDart;
    }

    return allPoints;
  }

  /// Append data points to GPU (for incremental facet loading).
  ///
  /// Calls JavaScript ggrsV3AppendDataPoints which adds points without
  /// replacing existing data.
  ///
  /// [loadId] is the history snapshot ID from PlotState, used to correctly
  /// place data even if viewport has changed during async load.
  static void appendDataPoints(
    String containerId,
    List<Map<String, dynamic>> points,
    Map<String, dynamic> facetRange,
    int loadId,
  ) {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject;
    final fn = bootstrapModule['ggrsV3AppendDataPoints'] as JSFunction;

    final jsPoints = points.map((p) => p.jsify()).toList().toJS;
    final jsFacetRange = facetRange.jsify();

    fn.callAsFunction(
      null,
      containerId.toJS,
      jsPoints,
      jsFacetRange,
      loadId.toJS,
    );
  }

  /// Ensure CubeQuery exists with given bindings (WASM-managed).
  static Future<String> ensureCubeQuery(
    JSObject renderer,
    String paramsJson,
  ) async {
    final promise = renderer.callMethod(
      'ensureCubeQuery'.toJS,
      paramsJson.toJS,
    ) as JSPromise;
    final result = await promise.toDart;
    return (result as JSString).toDart;
  }

  /// Initialize plot stream (async WASM call).
  static Future<String> initPlotStream(
    JSObject renderer,
    String configJson,
  ) async {
    final promise = renderer.callMethod(
      'initPlotStream'.toJS,
      configJson.toJS,
    ) as JSPromise;
    final result = await promise.toDart;
    return (result as JSString).toDart;
  }

  /// Cleanup GPU and interaction manager for a container.
  static void cleanup(String containerId) {
    final bootstrapModule = globalContext['ggrsV3'] as JSObject?;
    if (bootstrapModule == null) return;

    final cleanupFn = bootstrapModule['ggrsV3Cleanup'] as JSFunction;
    cleanupFn.callAsFunction(null, containerId.toJS);
  }
}
