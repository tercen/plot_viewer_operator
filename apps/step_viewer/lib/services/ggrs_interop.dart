import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

/// Dart↔JS bindings for GGRS WASM functions (exposed on `window` by bootstrap.js).
class GgrsInterop {
  GgrsInterop._();

  static Future<void> ensureWasmInitialized() {
    final promise =
        web.window.callMethod<JSPromise>('ensureWasmInitialized'.toJS);
    return promise.toDart;
  }

  static JSObject createRenderer(String canvasId) {
    return web.window
        .callMethod<JSObject>('createGGRSRenderer'.toJS, canvasId.toJS);
  }

  static JSFunction createTextMeasurer() {
    return web.window
        .callMethod<JSFunction>('ggrsCreateTextMeasurer'.toJS);
  }

  static void initializeTercen(
      JSObject renderer, String serviceUri, String token) {
    renderer.callMethod<JSAny?>(
        'initializeTercen'.toJS, serviceUri.toJS, token.toJS);
  }

  /// Async: discover domain tables, fetch metadata, create PlotGenerator.
  /// Returns { n_rows, n_col_facets, n_row_facets, total_col_facets, total_row_facets }.
  static Future<JSObject> initPlotStream(
      JSObject renderer, String configJson) async {
    final promise = web.window.callMethod<JSPromise>(
        'ggrsInitPlotStream'.toJS, renderer, configJson.toJS);
    final result = await promise.toDart;
    return result! as JSObject;
  }

  /// Sync: compute layout from cached PlotGenerator.
  /// Uses callMethodVarArgs (5 args exceed callMethod's 4-arg limit).
  static JSObject getStreamLayout(
    JSObject renderer, double width, double height,
    String viewportJson, JSFunction measureTextFn,
  ) {
    return (web.window as JSObject).callMethodVarArgs<JSObject>(
      'ggrsGetStreamLayout'.toJS,
      [renderer, width.toJS, height.toJS, viewportJson.toJS, measureTextFn],
    );
  }

  /// Async: fetch chunk, dequantize, pixel-map, cull → { points, done, loaded }.
  static Future<JSObject> loadAndMapChunk(
      JSObject renderer, int chunkSize) async {
    final promise = web.window.callMethod<JSPromise>(
        'ggrsLoadAndMapChunk'.toJS, renderer, chunkSize.toJS);
    final result = await promise.toDart;
    return result! as JSObject;
  }

  /// Stateless layout (Phase 1 chrome, no Tercen connection).
  static JSObject computeLayout(
    JSObject renderer, String dataJson, double width, double height,
    JSFunction measureTextFn,
  ) {
    return (web.window as JSObject).callMethodVarArgs<JSObject>(
      'ggrsComputeLayout'.toJS,
      [renderer, dataJson.toJS, width.toJS, height.toJS, measureTextFn],
    );
  }

  /// Phase 1: SVG + DOM text chrome.
  static void renderChrome(String containerId, JSObject layoutInfo) {
    web.window.callMethod<JSAny?>(
        'ggrsRenderChrome'.toJS, containerId.toJS, layoutInfo);
  }

  /// Streaming path: WebGPU chrome (backgrounds, lines, borders on GPU;
  /// text on Canvas 2D overlay). Async on first call (GPU init).
  static Future<void> renderChromeCanvas(
      String containerId, JSObject layoutInfo) async {
    final promise = web.window.callMethod<JSPromise>(
        'ggrsRenderChromeCanvas'.toJS, containerId.toJS, layoutInfo);
    await promise.toDart;
  }

  static void createChromeLayers(String containerId, JSObject layoutInfo) {
    web.window.callMethod<JSAny?>(
        'ggrsCreateChromeLayers'.toJS, containerId.toJS, layoutInfo);
  }

  static void renderChromeBatch(
      String containerId, JSObject layoutInfo, int startCell, int endCell) {
    web.window.callMethod<JSAny?>(
        'ggrsRenderChromeBatch'.toJS,
        containerId.toJS, layoutInfo, startCell.toJS, endCell.toJS);
  }

  static void renderDataPoints(
      String containerId, JSArray points, JSObject options) {
    web.window.callMethod<JSAny?>(
        'ggrsRenderDataPoints'.toJS, containerId.toJS, points, options);
  }

  static void clearDataCanvas(String containerId) {
    web.window.callMethod<JSAny?>(
        'ggrsClearDataCanvas'.toJS, containerId.toJS);
  }

  /// Attach viewport zoom/pan handlers to a GGRS container div.
  /// [onCommit] fires when the accumulated GPU transform should be committed
  /// to a semantic re-render (scale threshold exceeded, or pan gesture ended).
  static void attachViewportHandlers(
    String containerId,
    void Function(double scale, double panX, double panY, double originX,
            double originY)
        onCommit,
  ) {
    final jsOnCommit = ((JSNumber scale, JSNumber panX, JSNumber panY,
        JSNumber originX, JSNumber originY) {
      onCommit(
        scale.toDartDouble,
        panX.toDartDouble,
        panY.toDartDouble,
        originX.toDartDouble,
        originY.toDartDouble,
      );
    }).toJS;
    web.window.callMethod<JSAny?>(
      'ggrsAttachViewportHandlers'.toJS,
      containerId.toJS,
      jsOnCommit,
    );
  }

  /// Set the view transform on the GPU renderer (sub-ms visual update).
  static void setViewTransform(
      String containerId, double scale, double tx, double ty) {
    (web.window as JSObject).callMethodVarArgs<JSAny?>(
      'ggrsSetViewTransform'.toJS,
      [containerId.toJS, scale.toJS, tx.toJS, ty.toJS],
    );
  }

  /// Reset the view transform to identity on the GPU renderer.
  static void resetViewTransform(String containerId) {
    web.window.callMethod<JSAny?>(
        'ggrsResetViewTransform'.toJS, containerId.toJS);
  }

  /// Enter staging mode — subsequent GPU writes go to staging buffers.
  static void beginStaging(String containerId) {
    web.window
        .callMethod<JSAny?>('ggrsBeginStaging'.toJS, containerId.toJS);
  }

  /// Commit staged render — swap staging → active, reset scroll offset.
  static void commitRender(String containerId) {
    web.window
        .callMethod<JSAny?>('ggrsCommitRender'.toJS, containerId.toJS);
  }

  // ── Split-buffer API (Phase 1.2+) ─────────────────────────────────────────

  /// Compute skeleton dimensions. Caches PlotDimensions in WASM.
  /// Uses callMethodVarArgs (5 args exceed callMethod's 4-arg limit).
  static JSObject computeSkeleton(
    JSObject renderer, double width, double height,
    String viewportJson, JSFunction measureTextFn,
  ) {
    return (web.window as JSObject).callMethodVarArgs<JSObject>(
      'ggrsComputeSkeleton'.toJS,
      [renderer, width.toJS, height.toJS, viewportJson.toJS, measureTextFn],
    );
  }

  /// Get static chrome layout (axes, ticks, column strips, title, labels).
  static JSObject getStaticChrome(JSObject renderer) {
    return web.window
        .callMethod<JSObject>('ggrsGetStaticChrome'.toJS, renderer);
  }

  /// Get viewport chrome layout (panels, grid, row strips, borders).
  static JSObject getViewportChrome(
      JSObject renderer, String viewportJson) {
    return web.window.callMethod<JSObject>(
        'ggrsGetViewportChrome'.toJS, renderer, viewportJson.toJS);
  }

  /// Render static chrome: creates DOM + GPU on first call, writes static buffer + text.
  static Future<void> renderStaticChrome(
      String containerId, JSObject layoutInfo) async {
    final promise = web.window.callMethod<JSPromise>(
        'ggrsRenderStaticChrome'.toJS, containerId.toJS, layoutInfo);
    await promise.toDart;
  }

  /// Render viewport chrome: replaces viewport GPU buffer + text, clears viewport points.
  static void renderViewportChrome(
      String containerId, JSObject layoutInfo) {
    web.window.callMethod<JSAny?>(
        'ggrsRenderViewportChrome'.toJS, containerId.toJS, layoutInfo);
  }

  /// Clear viewport chrome + data points + text.
  static void clearViewport(String containerId) {
    web.window
        .callMethod<JSAny?>('ggrsClearViewport'.toJS, containerId.toJS);
  }

  /// Clear all split buffers (static + viewport) + text.
  static void clearAll(String containerId) {
    web.window
        .callMethod<JSAny?>('ggrsClearAll'.toJS, containerId.toJS);
  }

  /// Yield to browser via requestAnimationFrame (fires before next paint).
  static Future<void> yieldFrame() {
    final completer = Completer<void>();
    web.window.requestAnimationFrame(
      ((JSNumber timestamp) { completer.complete(); }).toJS,
    );
    return completer.future;
  }
}
