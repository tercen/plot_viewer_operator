/* tslint:disable */
/* eslint-disable */

export class GGRSRenderer {
  free(): void;
  [Symbol.dispose](): void;
  /**
   * Compute layout from JSON payload (estimate text measurer).
   * Used for Phase 1 instant chrome — no Tercen connection needed.
   */
  computeLayout(data_json: string, width: number, height: number): string;
  /**
   * Load a chunk of data and return data-space coordinates (no pixel mapping).
   *
   * Same fetch + dequantize as loadAndMapChunk, but skips pixel mapping
   * and culling — the GPU vertex shader handles data→pixel projection.
   *
   * Returns JSON:
   * ```json
   * {
   *   "points": [{"x": 1.23, "y": 4.56, "ci": 0, "ri": 0}, ...],
   *   "done": false,
   *   "loaded": 15000,
   *   "total": 100000
   * }
   * ```
   */
  loadDataChunk(chunk_size: number): Promise<string>;
  /**
   * Compute skeleton: PlotDimensions + scale breaks. Caches result for
   * getStaticChrome() and getViewportChrome().
   *
   * Returns JSON: { margins: {left,right,top,bottom}, panel_grid: {cell_width,
   * cell_height, cell_spacing, offset_x, offset_y, n_cols, n_rows},
   * final_width, final_height }
   */
  computeSkeleton(width: number, height: number, viewport_json: string, measure_text_fn: Function): string;
  /**
   * Initialize plot stream: fetch metadata, create WasmStreamGenerator + PlotGenerator.
   *
   * Input JSON:
   * ```json
   * {
   *   "tables": { "qt": "...", "column": "...", "row": "...", "y": "...", ... },
   *   "bindings": { "x": {...}, "y": {...}, "color": {...}, ... },
   *   "geom_type": "point",
   *   "theme": "gray",
   *   "x_label": "measurement",
   *   "y_label": "value"
   * }
   * ```
   *
   * `tables` is a queryTableType → table ID map, classified by Dart from
   * `CubeQueryTableSchema.queryTableType`. Keys: "qt", "column", "row", "x", "y".
   *
   * Returns metadata JSON:
   * ```json
   * { "n_rows": N, "n_col_facets": C, "n_row_facets": R }
   * ```
   */
  initPlotStream(config_json: string): Promise<string>;
  /**
   * Get static chrome (axes, title, column strips) from cached skeleton.
   *
   * Returns LayoutInfo JSON with only static elements populated.
   * Must call computeSkeleton() first.
   */
  getStaticChrome(): string;
  /**
   * Compute layout from cached PlotGenerator. Caches the result for
   * pixel mapping in loadAndMapChunk.
   *
   * Returns LayoutInfo JSON (same format as computeLayout).
   */
  getStreamLayout(width: number, height: number, viewport_json: string, measure_text_fn: Function): string;
  /**
   * Initialize the Tercen HTTP client.
   *
   * Must be called before `initPlotStream()`.
   */
  initializeTercen(service_uri: string, token: string): void;
  /**
   * Load a chunk of data, dequantize, pixel-map, cull, and return visible points.
   *
   * Must call getStreamLayout() or getViewportChrome() before this to cache the layout.
   * Call repeatedly until `done` is true.
   *
   * Returns JSON:
   * ```json
   * {
   *   "points": [{"panel_idx": 0, "px": 123.4, "py": 456.7}, ...],
   *   "done": false,
   *   "loaded": 15000,
   *   "total": 100000,
   *   "stats": {"total": 15000, "after_cull": 8000}
   * }
   * ```
   */
  loadAndMapChunk(chunk_size: number): Promise<string>;
  /**
   * Get viewport chrome (panels, grid, row strips, axis mappings) for a viewport.
   *
   * Returns LayoutInfo JSON with only viewport elements populated.
   * Caches axis_mappings for use by loadAndMapChunk().
   * Must call computeSkeleton() first.
   */
  getViewportChrome(viewport_json: string): string;
  /**
   * Compute layout with viewport filtering + browser text measurement.
   */
  computeLayoutViewport(data_json: string, width: number, height: number, viewport_json: string, measure_text_fn: Function): string;
  /**
   * Compute tick positions and labels for a given axis range.
   *
   * Lightweight sync function (<1ms). Uses cached PlotGenerator from
   * initPlotStream. Respects the Y-axis scale type (log, sqrt, discrete, etc.).
   *
   * Returns JSON:
   * ```json
   * {
   *   "x_breaks": [0.0, 1.0, 2.0],
   *   "x_labels": ["0", "1", "2"],
   *   "y_breaks": [10.0, 20.0, 30.0],
   *   "y_labels": ["10", "20", "30"]
   * }
   * ```
   */
  computeTicksForRange(x_min: number, x_max: number, y_min: number, y_max: number): string;
  /**
   * Compute layout with browser text measurement.
   * Used for Phase 1 instant chrome with accurate text sizing.
   */
  computeLayoutWithMeasurer(data_json: string, width: number, height: number, measure_text_fn: Function): string;
  /**
   * Create a new GGRS renderer
   */
  constructor(canvas_id: string);
  /**
   * Get renderer info for debugging
   */
  info(): string;
}

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
  readonly memory: WebAssembly.Memory;
  readonly __wbg_ggrsrenderer_free: (a: number, b: number) => void;
  readonly ggrsrenderer_computeLayout: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
  readonly ggrsrenderer_computeLayoutViewport: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => void;
  readonly ggrsrenderer_computeLayoutWithMeasurer: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => void;
  readonly ggrsrenderer_computeSkeleton: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => void;
  readonly ggrsrenderer_computeTicksForRange: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
  readonly ggrsrenderer_getStaticChrome: (a: number, b: number) => void;
  readonly ggrsrenderer_getStreamLayout: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => void;
  readonly ggrsrenderer_getViewportChrome: (a: number, b: number, c: number, d: number) => void;
  readonly ggrsrenderer_info: (a: number, b: number) => void;
  readonly ggrsrenderer_initPlotStream: (a: number, b: number, c: number) => number;
  readonly ggrsrenderer_initializeTercen: (a: number, b: number, c: number, d: number, e: number) => void;
  readonly ggrsrenderer_loadAndMapChunk: (a: number, b: number) => number;
  readonly ggrsrenderer_loadDataChunk: (a: number, b: number) => number;
  readonly ggrsrenderer_new: (a: number, b: number) => number;
  readonly __wasm_bindgen_func_elem_954: (a: number, b: number, c: number) => void;
  readonly __wasm_bindgen_func_elem_939: (a: number, b: number) => void;
  readonly __wasm_bindgen_func_elem_36361: (a: number, b: number, c: number, d: number) => void;
  readonly __wbindgen_export: (a: number, b: number) => number;
  readonly __wbindgen_export2: (a: number, b: number, c: number, d: number) => number;
  readonly __wbindgen_export3: (a: number) => void;
  readonly __wbindgen_export4: (a: number, b: number, c: number) => void;
  readonly __wbindgen_add_to_stack_pointer: (a: number) => number;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
* Instantiates the given `module`, which can either be bytes or
* a precompiled `WebAssembly.Module`.
*
* @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
*
* @returns {InitOutput}
*/
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
* If `module_or_path` is {RequestInfo} or {URL}, makes a request and
* for everything else, calls `WebAssembly.instantiate` directly.
*
* @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
*
* @returns {Promise<InitOutput>}
*/
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
