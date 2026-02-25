import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

/// Dart↔JS bindings for GGRS V2 data-space GPU rendering.
///
/// Reuses v1 WASM init, renderer creation, text measurer, computeLayout,
/// renderChrome, initPlotStream, computeSkeleton, getStaticChrome, getViewportChrome.
/// V2 additions: GPU setup, panel layout, chrome from layout, data chunk loading,
/// interaction attachment, and tick computation.
class GgrsInteropV2 {
  GgrsInteropV2._();

  // ── WASM init (reuses v1 window exports) ──────────────────────────────────

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

  // ── Stream init (reuses v1) ───────────────────────────────────────────────

  static Future<JSObject> initPlotStream(
      JSObject renderer, String configJson) async {
    final promise = web.window.callMethod<JSPromise>(
        'ggrsInitPlotStream'.toJS, renderer, configJson.toJS);
    final result = await promise.toDart;
    return result! as JSObject;
  }

  // ── Phase 1: chrome (reuses v1 WASM functions) ────────────────────────────

  static JSObject computeLayout(
    JSObject renderer, String dataJson, double width, double height,
    JSFunction measureTextFn,
  ) {
    return (web.window as JSObject).callMethodVarArgs<JSObject>(
      'ggrsComputeLayout'.toJS,
      [renderer, dataJson.toJS, width.toJS, height.toJS, measureTextFn],
    );
  }

  static void renderChrome(String containerId, JSObject layoutInfo) {
    web.window.callMethod<JSAny?>(
        'ggrsRenderChrome'.toJS, containerId.toJS, layoutInfo);
  }

  // ── Skeleton + split chrome (reuses v1 WASM functions) ────────────────────

  static JSObject computeSkeleton(
    JSObject renderer, double width, double height,
    String viewportJson, JSFunction measureTextFn,
  ) {
    return (web.window as JSObject).callMethodVarArgs<JSObject>(
      'ggrsComputeSkeleton'.toJS,
      [renderer, width.toJS, height.toJS, viewportJson.toJS, measureTextFn],
    );
  }

  static JSObject getStaticChrome(JSObject renderer) {
    return web.window
        .callMethod<JSObject>('ggrsGetStaticChrome'.toJS, renderer);
  }

  static JSObject getViewportChrome(
      JSObject renderer, String viewportJson) {
    return web.window.callMethod<JSObject>(
        'ggrsGetViewportChrome'.toJS, renderer, viewportJson.toJS);
  }

  // ── V2 GPU setup ──────────────────────────────────────────────────────────

  /// Idempotent GPU init. First call creates 3-layer DOM + WebGPU.
  /// Subsequent calls resize canvases and update uniforms.
  static Future<void> ensureGpu(
      String containerId, double width, double height) async {
    final promise = web.window.callMethod<JSPromise>(
        'ggrsV2EnsureGpu'.toJS, containerId.toJS, width.toJS, height.toJS);
    await promise.toDart;
  }

  static void setPanelLayout(String containerId, JSObject params) {
    web.window.callMethod<JSAny?>(
        'ggrsV2SetPanelLayout'.toJS, containerId.toJS, params);
  }

  static void setChromeFromLayout(String containerId, JSObject layoutInfo) {
    web.window.callMethod<JSAny?>(
        'ggrsV2SetChromeFromLayout'.toJS, containerId.toJS, layoutInfo);
  }

  /// Merge static + viewport chrome in JS (no Dart serialization).
  static void mergeAndSetChrome(
      String containerId, JSObject staticChrome, JSObject vpChrome) {
    (web.window as JSObject).callMethodVarArgs<JSAny?>(
      'ggrsV2MergeAndSetChrome'.toJS,
      [containerId.toJS, staticChrome, vpChrome],
    );
  }

  // ── V2 scroll / facet viewport ─────────────────────────────────────────

  static void setScrollOffset(String containerId, double dx, double dy) {
    (web.window as JSObject).callMethodVarArgs<JSAny?>(
      'ggrsV2SetScrollOffset'.toJS,
      [containerId.toJS, dx.toJS, dy.toJS],
    );
  }

  static void setFacetViewport(
      String containerId, int colStart, int rowStart) {
    (web.window as JSObject).callMethodVarArgs<JSAny?>(
      'ggrsV2SetFacetViewport'.toJS,
      [containerId.toJS, colStart.toJS, rowStart.toJS],
    );
  }

  // ── V2 data streaming ─────────────────────────────────────────────────────

  /// Stream all data in JS — no Dart round-trips per chunk.
  /// Returns JSObject with { cancelled: bool, loaded?: int }.
  static Future<JSObject> streamAllData(
      String containerId, JSObject renderer, int chunkSize,
      JSObject options) async {
    final promise = (web.window as JSObject).callMethodVarArgs<JSPromise>(
      'ggrsV2StreamAllData'.toJS,
      [containerId.toJS, renderer, chunkSize.toJS, options],
    );
    final result = await promise.toDart;
    return result! as JSObject;
  }

  /// Cancel any in-flight JS streaming loop for a container.
  static void cancelStreaming(String containerId) {
    web.window.callMethod<JSAny?>(
        'ggrsV2CancelStreaming'.toJS, containerId.toJS);
  }

  // ── V2 interaction ────────────────────────────────────────────────────────

  static void attachInteraction(
    String containerId,
    JSObject renderer,
    JSObject staticChrome,
    JSObject vpChrome,
  ) {
    (web.window as JSObject).callMethodVarArgs<JSAny?>(
      'ggrsV2AttachInteraction'.toJS,
      [containerId.toJS, renderer, staticChrome, vpChrome],
    );
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  static void clearAll(String containerId) {
    web.window
        .callMethod<JSAny?>('ggrsV2ClearAll'.toJS, containerId.toJS);
  }

  // ── Utility ───────────────────────────────────────────────────────────────

  static Future<void> yieldFrame() {
    final completer = Completer<void>();
    web.window.requestAnimationFrame(
      ((JSNumber timestamp) { completer.complete(); }).toJS,
    );
    return completer.future;
  }
}
