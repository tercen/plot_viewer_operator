/**
 * GGRS V2 Bootstrap — data-space GPU rendering with named layers.
 *
 * DOM structure:
 *   <canvas class="ggrs-gpu">              WebGPU: named rect layers + data points
 *   <canvas class="ggrs-text-labels">      Canvas 2D: title, axis labels, strip labels (static)
 *   <canvas class="ggrs-text-ticks">       Canvas 2D: tick labels (updated on zoom/pan)
 *   <div class="ggrs-interaction">         mouse/touch events (zoom/pan in JS)
 *
 * GPU rect layers (drawn in registration order):
 *   panel_backgrounds, strip_backgrounds, grid_lines, axis_lines, tick_marks, panel_borders
 *
 * On zoom, only cell size changes (GPU uniform write). Chrome layers rebuild
 * on debounce. Static layers (labels) are untouched.
 */

import { GgrsGpuV2 } from "./ggrs_gpu_v2.js";

// ─── Per-container state ───────────────────────────────────────────────────────

const _containers = {};  // containerId → { gpu, panelLayout, interactionCleanup }

// ─── Helpers (same as v1 bootstrap) ────────────────────────────────────────────

function _applyLayerStyle(el, w, h) {
    el.style.position = 'absolute';
    el.style.left = '0';
    el.style.top = '0';
    el.style.width = w + 'px';
    el.style.height = h + 'px';
    el.style.pointerEvents = 'none';
}

function _drawTextPlacement(ctx, tp) {
    ctx.save();
    ctx.font = `${tp.font_weight || 'normal'} ${tp.font_size}px ${tp.font_family}`;
    ctx.fillStyle = tp.color;

    switch (tp.anchor) {
        case 'middle': ctx.textAlign = 'center'; break;
        case 'end':    ctx.textAlign = 'right';  break;
        default:       ctx.textAlign = 'left';   break;
    }
    switch (tp.baseline) {
        case 'central':    ctx.textBaseline = 'middle';      break;
        case 'auto':       ctx.textBaseline = 'alphabetic';  break;
        case 'hanging':    ctx.textBaseline = 'hanging';     break;
        default:           ctx.textBaseline = 'alphabetic';  break;
    }

    if (tp.rotation && tp.rotation !== 0) {
        ctx.translate(tp.x, tp.y);
        ctx.rotate(tp.rotation * Math.PI / 180);
        ctx.fillText(tp.text, 0, 0);
    } else {
        ctx.fillText(tp.text, tp.x, tp.y);
    }
    ctx.restore();
}

function _drawTextsOnCanvas(canvas, texts, dpr, scrollX, scrollY) {
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.translate(-(scrollX || 0), -(scrollY || 0));  // surface → screen
    for (const tp of texts) {
        _drawTextPlacement(ctx, tp);
    }
}

function _parseColor(str) {
    if (str && str.startsWith('#')) {
        const hex = str.slice(1);
        const r = parseInt(hex.slice(0, 2), 16) / 255;
        const g = parseInt(hex.slice(2, 4), 16) / 255;
        const b = parseInt(hex.slice(4, 6), 16) / 255;
        const a = hex.length > 6 ? parseInt(hex.slice(6, 8), 16) / 255 : 1.0;
        return [r, g, b, a];
    }
    if (str && str.startsWith('rgba(')) {
        const parts = str.slice(5, -1).split(',').map(s => s.trim());
        return [parseInt(parts[0]) / 255, parseInt(parts[1]) / 255,
                parseInt(parts[2]) / 255, parseFloat(parts[3])];
    }
    if (str && str.startsWith('rgb(')) {
        const parts = str.slice(4, -1).split(',').map(s => s.trim());
        return [parseInt(parts[0]) / 255, parseInt(parts[1]) / 255,
                parseInt(parts[2]) / 255, 1.0];
    }
    throw new Error('[GGRS-V2] _parseColor: unrecognized color: ' + JSON.stringify(str));
}

function _lineToRect(ln) {
    const lw = ln.width || 1;
    const hw = lw / 2;
    const dx = ln.x2 - ln.x1;
    const dy = ln.y2 - ln.y1;
    if (Math.abs(dy) < 0.001) {
        return { x: Math.min(ln.x1, ln.x2), y: ln.y1 - hw, w: Math.abs(dx), h: lw };
    }
    return { x: ln.x1 - hw, y: Math.min(ln.y1, ln.y2), w: lw, h: Math.abs(dy) };
}

// ─── Canvas layer resizing (no DOM recreation) ──────────────────────────────

function _resizeCanvasLayers(containerId, width, height) {
    const container = document.getElementById(containerId);
    if (!container) return;
    const state = _containers[containerId];

    const dpr = window.devicePixelRatio || 1;

    container.style.width = width + 'px';
    container.style.height = height + 'px';

    // Resize all named text canvases
    if (state && state.textLayers) {
        for (const canvas of Object.values(state.textLayers)) {
            canvas.width = Math.round(width * dpr);
            canvas.height = Math.round(height * dpr);
            canvas.style.width = width + 'px';
            canvas.style.height = height + 'px';
        }
    }

    const interactionDiv = container.querySelector('.ggrs-interaction');
    if (interactionDiv) {
        interactionDiv.style.width = width + 'px';
        interactionDiv.style.height = height + 'px';
    }
}

// ─── Named text layer management ──────────────────────────────────────────────

/**
 * Set (create or replace) a named text layer. Each text layer is its own
 * <canvas> element — clearing one doesn't touch the other.
 */
function _setTextLayer(containerId, name, textPlacements) {
    const state = _containers[containerId];
    if (!state) return;
    const container = document.getElementById(containerId);
    if (!container) return;

    const dpr = window.devicePixelRatio || 1;
    let canvas = state.textLayers[name];

    if (!canvas) {
        // Create new canvas, insert before interaction div
        canvas = document.createElement('canvas');
        canvas.className = 'ggrs-text-' + name;
        const w = state.gpu._width;
        const h = state.gpu._height;
        canvas.width = Math.round(w * dpr);
        canvas.height = Math.round(h * dpr);
        _applyLayerStyle(canvas, w, h);

        const interactionDiv = container.querySelector('.ggrs-interaction');
        container.insertBefore(canvas, interactionDiv);
        state.textLayers[name] = canvas;
    }

    // Cache placements for scroll redraws
    state.textPlacementCache[name] = textPlacements || [];

    // Clear and redraw with current scroll
    _drawTextsOnCanvas(canvas, textPlacements || [], dpr, state.scrollX, state.scrollY);
}

/**
 * Clear a named text layer (if it exists).
 */
function _clearTextLayer(containerId, name) {
    const state = _containers[containerId];
    if (!state) return;
    const canvas = state.textLayers[name];
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
}

/**
 * Redraw all cached text layers with the current scroll offset.
 * Called on scroll events between chrome recomputes for instant text updates.
 */
function _redrawTextWithScroll(containerId) {
    const state = _containers[containerId];
    if (!state) return;
    const dpr = window.devicePixelRatio || 1;
    for (const [name, placements] of Object.entries(state.textPlacementCache)) {
        const canvas = state.textLayers[name];
        if (canvas && placements) {
            _drawTextsOnCanvas(canvas, placements, dpr, state.scrollX, state.scrollY);
        }
    }
}

// ─── Per-type rect builders ──────────────────────────────────────────────────

function _buildRectLayerFromBackgrounds(backgrounds) {
    const rects = [];
    for (const p of backgrounds || []) {
        const [r, g, b, a] = _parseColor(p.fill);
        rects.push({ x: p.x, y: p.y, width: p.width, height: p.height, color: [r, g, b, a] });
    }
    return rects;
}

function _buildRectLayerFromLines(lines) {
    const rects = [];
    for (const ln of lines || []) {
        const rect = _lineToRect(ln);
        const [r, g, b, a] = _parseColor(ln.color);
        rects.push({ x: rect.x, y: rect.y, width: rect.w, height: rect.h, color: [r, g, b, a] });
    }
    return rects;
}

function _buildRectLayerFromBorders(borders) {
    const rects = [];
    for (const pb of borders || []) {
        const sw = pb.stroke_width || 1;
        const [r, g, b, a] = _parseColor(pb.color);
        const c = [r, g, b, a];
        rects.push({ x: pb.x, y: pb.y, width: pb.width, height: sw, color: c });
        rects.push({ x: pb.x, y: pb.y + pb.height - sw, width: pb.width, height: sw, color: c });
        rects.push({ x: pb.x, y: pb.y + sw, width: sw, height: pb.height - 2 * sw, color: c });
        rects.push({ x: pb.x + pb.width - sw, y: pb.y + sw, width: sw, height: pb.height - 2 * sw, color: c });
    }
    return rects;
}

// ─── View chrome rebuild (from WASM ViewState) ──────────────────────────────

/**
 * Rebuild all chrome from WASM ViewState (V3 merged: static + viewport).
 * Called on zoom (immediate) and scroll (debounced).
 * WASM getViewChrome() returns merged chrome with all fields.
 */
function _rebuildViewChrome(containerId) {
    const state = _containers[containerId];
    if (!state || !state.renderer) return;

    const json = state.renderer.getViewChrome();
    const chrome = JSON.parse(json);
    if (chrome.error) {
        console.error('[GGRS-V2] getViewChrome failed:', chrome.error);
        return;
    }

    const gpu = state.gpu;

    // Plot background clear color
    if (chrome.plot_background) {
        const [r, g, b, a] = _parseColor(chrome.plot_background);
        gpu._clearColor = { r, g, b, a };
    }

    // Rect layers (surface coords, shader scrolls them)
    gpu.setLayer('panel_backgrounds',
        _buildRectLayerFromBackgrounds(chrome.panel_backgrounds));
    gpu.setLayer('strip_backgrounds',
        _buildRectLayerFromBackgrounds(chrome.strip_backgrounds));
    gpu.setLayer('grid_lines',
        _buildRectLayerFromLines(chrome.grid_lines));
    gpu.setLayer('axis_lines',
        _buildRectLayerFromLines(chrome.axis_lines));
    gpu.setLayer('tick_marks',
        _buildRectLayerFromLines(chrome.tick_marks));
    gpu.setLayer('panel_borders',
        _buildRectLayerFromBorders(chrome.panel_borders));

    // Text layers (surface coords, manual scroll via _drawTextsOnCanvas)
    const labels = [];
    if (chrome.title) labels.push(chrome.title);
    if (chrome.x_label) labels.push(chrome.x_label);
    if (chrome.y_label) labels.push(chrome.y_label);
    _setTextLayer(containerId, 'labels', labels);
    _setTextLayer(containerId, 'strip_labels', chrome.strip_labels || []);
    _setTextLayer(containerId, 'ticks', [
        ...(chrome.x_ticks || []),
        ...(chrome.y_ticks || []),
    ]);

    gpu.requestRedraw();
}

// ─── V2 window exports ─────────────────────────────────────────────────────────

/**
 * Ensure GPU is initialized for a container. Idempotent:
 * - First call: creates 3-layer DOM + inits WebGPU.
 * - Subsequent calls: resizes canvases and updates uniforms.
 */
async function ggrsV2EnsureGpu(containerId, width, height) {
    const existing = _containers[containerId];
    if (existing && existing.gpu && existing.gpu._device) {
        // Resize only — GPU already initialized
        existing.gpu.setCanvasSize(width, height);
        _resizeCanvasLayers(containerId, width, height);
        return;
    }

    // First time — create 3-layer DOM + init WebGPU
    const container = document.getElementById(containerId);
    if (!container) throw new Error('[GGRS-V2] Container not found: ' + containerId);

    const dpr = window.devicePixelRatio || 1;

    // Clean up existing interaction handlers if any
    if (existing && existing.interactionCleanup) {
        existing.interactionCleanup();
    }
    container.innerHTML = '';

    container.style.position = 'relative';
    container.style.width = width + 'px';
    container.style.height = height + 'px';
    container.style.overflow = 'hidden';

    // Layer 0: WebGPU canvas (all rect layers + data points)
    const gpuCanvas = document.createElement('canvas');
    gpuCanvas.className = 'ggrs-gpu';
    gpuCanvas.width = Math.round(width * dpr);
    gpuCanvas.height = Math.round(height * dpr);
    _applyLayerStyle(gpuCanvas, width, height);
    container.appendChild(gpuCanvas);

    // Text canvases are created on demand by _setTextLayer (between gpu and interaction)

    // Interaction div (always last in DOM)
    const interactionDiv = document.createElement('div');
    interactionDiv.className = 'ggrs-interaction';
    _applyLayerStyle(interactionDiv, width, height);
    interactionDiv.style.pointerEvents = 'auto';
    container.appendChild(interactionDiv);

    // Init GPU
    const gpu = new GgrsGpuV2();
    await gpu.init(gpuCanvas);
    gpu.setCanvasSize(width, height);

    // Store state
    _containers[containerId] = {
        gpu,
        panelLayout: null,
        interactionCleanup: null,
        interactionAttached: false,
        renderer: null,
        textLayers: {},           // name → <canvas> element
        textPlacementCache: {},   // name → Array<TextPlacement>
        scrollX: 0,              // current total scroll (V3)
        scrollY: 0,
        streamingToken: 0,
    };

    // Update plot_background clear color
    gpu._clearColor = { r: 1, g: 1, b: 1, a: 1 };
}

/**
 * Set panel layout — writes full 80-byte view uniform.
 * Called after initPlotStream when panel dimensions are known.
 */
function ggrsV2SetPanelLayout(containerId, params) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);

    state.panelLayout = { ...params };
    state.gpu.setViewUniforms(params);

    // Reset scroll
    state.scrollX = 0;
    state.scrollY = 0;
}

/**
 * Merge static + viewport chrome and set as independent named layers.
 * Each chrome category → its own GPU rect layer + text layer.
 * Caches style info for zoom chrome rebuilds.
 */
function ggrsV2MergeAndSetChrome(containerId, staticChrome, vpChrome) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);

    const gpu = state.gpu;

    // Clear color from plot_background
    const plotBg = staticChrome.plot_background ?? vpChrome.plot_background;
    if (plotBg) {
        const [r, g, b, a] = _parseColor(plotBg);
        gpu._clearColor = { r, g, b, a };
    }

    // Rect layers (each independent, z-order = call order)
    gpu.setLayer('panel_backgrounds',
        _buildRectLayerFromBackgrounds(vpChrome.panel_backgrounds));
    gpu.setLayer('strip_backgrounds',
        _buildRectLayerFromBackgrounds([
            ...(staticChrome.strip_backgrounds || []),
            ...(vpChrome.strip_backgrounds || []),
        ]));
    gpu.setLayer('grid_lines',
        _buildRectLayerFromLines([
            ...(staticChrome.grid_lines || []),
            ...(vpChrome.grid_lines || []),
        ]));
    gpu.setLayer('axis_lines',
        _buildRectLayerFromLines([
            ...(staticChrome.axis_lines || []),
            ...(vpChrome.axis_lines || []),
        ]));
    gpu.setLayer('tick_marks',
        _buildRectLayerFromLines([
            ...(staticChrome.tick_marks || []),
            ...(vpChrome.tick_marks || []),
        ]));
    gpu.setLayer('panel_borders',
        _buildRectLayerFromBorders(vpChrome.panel_borders));

    // Text layers (each independent canvas)
    // Static labels (title, axis labels) — don't change on zoom
    const labelTexts = [];
    if (staticChrome.title) labelTexts.push(staticChrome.title);
    if (staticChrome.x_label) labelTexts.push(staticChrome.x_label);
    if (staticChrome.y_label) labelTexts.push(staticChrome.y_label);
    _setTextLayer(containerId, 'labels', labelTexts);

    // Strip labels — change when n_visible changes (multi-facet zoom)
    const stripLabelTexts = [
        ...(staticChrome.strip_labels || []),
        ...(vpChrome.strip_labels || []),
    ];
    _setTextLayer(containerId, 'strip_labels', stripLabelTexts);

    const tickTexts = [
        ...(staticChrome.x_ticks || []), ...(vpChrome.x_ticks || []),
        ...(staticChrome.y_ticks || []), ...(vpChrome.y_ticks || []),
    ];
    _setTextLayer(containerId, 'ticks', tickTexts);

}

/**
 * Append data-space points to the GPU buffer.
 */
function ggrsV2AppendDataPoints(containerId, points, options) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);
    state.gpu.appendDataPoints(points, options);
}

/**
 * Clear data points from the GPU buffer.
 */
function ggrsV2ClearDataPoints(containerId) {
    const state = _containers[containerId];
    if (!state) return;
    state.gpu.clearDataPoints();
}

/**
 * Attach V3 interaction handlers. Attach-once: if already attached, just update
 * the renderer ref (no handler re-creation).
 *
 * Wheel            → vertical scroll (WASM scroll → GPU uniform → debounced chrome)
 * Ctrl+wheel       → horizontal scroll
 * Shift+wheel      → zoom with anchor (zone-dependent):
 *   - Left strip (x < gridOriginX)  → Y only
 *   - Top strip  (y < gridOriginY)  → X only
 *   - Inside grid                    → both
 * Double-click     → reset to initial cell sizes + scroll
 *
 * Data points reproject instantly via GPU uniform write.
 * Chrome rects shift via rect shader scroll_offset (GPU, instant).
 * Text redraws via cached placements + new scroll offset (<1ms).
 * Chrome recompute: immediate for zoom, debounced for scroll.
 *
 * @param {string} containerId
 * @param {Object} renderer - WASM GGRSRenderer
 */
function ggrsV2AttachInteraction(containerId, renderer) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);

    // Always update renderer ref (needed when bindings change)
    state.renderer = renderer;

    if (state.interactionAttached) return;  // handlers already wired
    state.interactionAttached = true;

    const container = document.getElementById(containerId);
    const interactionDiv = container.querySelector('.ggrs-interaction');
    if (!interactionDiv) throw new Error('[GGRS-V2] Interaction div not found');

    const gpu = state.gpu;

    let chromeTimer = null;
    const CHROME_DEBOUNCE = 150; // ms

    function applySnapshot(snapshot) {
        // Point shader uniforms
        gpu.setAxisRange(snapshot.vis_x_min, snapshot.vis_x_max,
                         snapshot.vis_y_min, snapshot.vis_y_max);
        gpu.setCellSize(snapshot.cell_width, snapshot.cell_height);
        gpu.setVisibleCounts(snapshot.n_visible_cols, snapshot.n_visible_rows);
        gpu.setFacetViewport(snapshot.viewport_col_start, snapshot.viewport_row_start);
        gpu.setScrollOffset(snapshot.scroll_offset_x, snapshot.scroll_offset_y); // point shader sub-cell
        // Rect shader scroll
        gpu.setRectScroll(snapshot.scroll_x, snapshot.scroll_y);
        // Track scroll in state for text redraws
        state.scrollX = snapshot.scroll_x;
        state.scrollY = snapshot.scroll_y;
    }

    function scheduleChromeRebuild() {
        clearTimeout(chromeTimer);
        chromeTimer = setTimeout(() => _rebuildViewChrome(containerId), CHROME_DEBOUNCE);
    }

    function getMousePos(e) {
        const rect = interactionDiv.getBoundingClientRect();
        return { x: e.clientX - rect.left, y: e.clientY - rect.top };
    }

    // ── Wheel handler ─────────────────────────────────────────────────────

    function onWheel(e) {
        e.preventDefault();
        const pos = getMousePos(e);
        let snapshot;

        if (e.shiftKey) {
            // Shift+wheel → zoom with anchor (zone-dependent)
            const delta = e.deltaY !== 0 ? e.deltaY : e.deltaX;
            const sign = delta < 0 ? 1 : -1;
            const axis = (pos.x < gpu.gridOriginX) ? 'y'
                       : (pos.y < gpu.gridOriginY) ? 'x' : 'both';
            snapshot = JSON.parse(state.renderer.zoom(axis, sign));
        } else if (e.ctrlKey || e.metaKey) {
            // Ctrl+wheel → horizontal scroll
            snapshot = JSON.parse(state.renderer.scroll(e.deltaY, 0));
        } else {
            // Wheel → vertical scroll
            snapshot = JSON.parse(state.renderer.scroll(0, e.deltaY));
        }

        applySnapshot(snapshot);

        if (e.shiftKey) {
            // Zoom narrows axis range → chrome must recompute ticks immediately
            clearTimeout(chromeTimer);
            _rebuildViewChrome(containerId);
        } else {
            // Scroll: instant text update via cache, debounced chrome recompute
            _redrawTextWithScroll(containerId);
            scheduleChromeRebuild();
        }
    }

    // ── Double-click: reset to initial state ─────────────────────────────

    function onDblClick() {
        const snapshot = JSON.parse(state.renderer.resetView());
        applySnapshot(snapshot);
        clearTimeout(chromeTimer);
        _rebuildViewChrome(containerId);
    }

    interactionDiv.addEventListener('wheel', onWheel, { passive: false });
    interactionDiv.addEventListener('dblclick', onDblClick);

    state.interactionCleanup = () => {
        interactionDiv.removeEventListener('wheel', onWheel);
        interactionDiv.removeEventListener('dblclick', onDblClick);
        clearTimeout(chromeTimer);
        state.interactionAttached = false;
    };
}

/**
 * Clear everything for a container.
 */
function ggrsV2ClearAll(containerId) {
    const state = _containers[containerId];
    if (!state) return;
    state.gpu.clearAll();

    // Clear all named text canvases
    for (const name of Object.keys(state.textLayers)) {
        _clearTextLayer(containerId, name);
    }
}

/**
 * Load a data-space chunk from WASM. Returns parsed JSON.
 */
async function ggrsV2LoadDataChunk(renderer, chunkSize) {
    const json = await renderer.loadDataChunk(chunkSize);
    const result = JSON.parse(json);
    if (result.error) {
        throw new Error('[GGRS-V2] loadDataChunk failed: ' + result.error);
    }
    return result;
}

// ─── JS-side streaming loop ──────────────────────────────────────────────────

/**
 * Stream all data chunks in JS — no Dart round-trips per chunk.
 * Clears old data points first, then loops loadDataChunk until done.
 * Cancellable via streamingToken: if another stream starts (or
 * ggrsV2CancelStreaming is called), the old loop exits early.
 *
 * @returns {{ cancelled: boolean, loaded?: number }}
 */
async function ggrsV2StreamAllData(containerId, renderer, chunkSize, options) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);
    const token = ++state.streamingToken;  // cancel any prior stream

    // Clear old data points before streaming new ones
    state.gpu.clearDataPoints();

    const t0 = performance.now();
    let totalLoaded = 0;
    let chunkIndex = 0;
    console.log(`[GGRS-V2 timing] streamAllData START  chunkSize=${chunkSize}`);

    while (true) {
        if (state.streamingToken !== token) {
            console.log(`[GGRS-V2 timing] streamAllData CANCELLED after ${chunkIndex} chunks, ${totalLoaded} pts, ${(performance.now()-t0).toFixed(1)}ms`);
            return { cancelled: true };
        }

        const tChunk = performance.now();
        const json = await renderer.loadDataChunk(chunkSize);
        const tWasm = performance.now();
        const result = JSON.parse(json);
        const tParse = performance.now();
        if (result.error) throw new Error('[GGRS-V2] loadDataChunk: ' + result.error);

        if (state.streamingToken !== token) {
            console.log(`[GGRS-V2 timing] streamAllData CANCELLED after ${chunkIndex} chunks, ${totalLoaded} pts, ${(performance.now()-t0).toFixed(1)}ms`);
            return { cancelled: true };
        }

        const nPts = result.points ? result.points.length : 0;
        let tGpu = tParse;
        if (nPts > 0) {
            state.gpu.appendDataPoints(result.points, options);
            tGpu = performance.now();
            totalLoaded += nPts;
        }

        console.log(`[GGRS-V2 timing] chunk[${chunkIndex}]: ${nPts} pts  wasm=${(tWasm-tChunk).toFixed(1)}ms  parse=${(tParse-tWasm).toFixed(1)}ms  gpu=${(tGpu-tParse).toFixed(1)}ms  total=${(tGpu-tChunk).toFixed(1)}ms  cumPts=${totalLoaded}`);

        if (result.done) {
            const elapsed = performance.now() - t0;
            console.log(`[GGRS-V2 timing] streamAllData DONE  ${chunkIndex+1} chunks, ${totalLoaded} pts, ${elapsed.toFixed(1)}ms  (${totalLoaded > 0 ? (totalLoaded / elapsed * 1000).toFixed(0) : 0} pts/s)`);
            return { cancelled: false, loaded: totalLoaded };
        }

        const tFrame = performance.now();
        await new Promise(resolve => requestAnimationFrame(resolve));
        const tAfterFrame = performance.now();
        console.log(`[GGRS-V2 timing] chunk[${chunkIndex}] frame yield: ${(tAfterFrame-tFrame).toFixed(1)}ms`);

        chunkIndex++;
    }
}

/**
 * Stream all data using packed binary buffers (no JSON serialization).
 * Uses loadDataChunkPacked (Uint8Array, 16 bytes/point) instead of loadDataChunk (JSON string).
 */
async function ggrsV2StreamAllDataPacked(containerId, renderer, chunkSize, options) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);
    const token = ++state.streamingToken;

    state.gpu.clearDataPoints();

    const t0 = performance.now();
    let totalLoaded = 0;
    let chunkIndex = 0;
    console.log(`[GGRS-V2 timing] streamAllDataPacked START  chunkSize=${chunkSize}`);

    while (true) {
        if (state.streamingToken !== token) {
            console.log(`[GGRS-V2 timing] streamAllDataPacked CANCELLED after ${chunkIndex} chunks, ${totalLoaded} pts, ${(performance.now()-t0).toFixed(1)}ms`);
            return { cancelled: true };
        }

        const tChunk = performance.now();
        const result = await renderer.loadDataChunkPacked(chunkSize);
        const tWasm = performance.now();
        if (result.error) throw new Error('[GGRS-V2] loadDataChunkPacked: ' + result.error);

        if (state.streamingToken !== token) {
            console.log(`[GGRS-V2 timing] streamAllDataPacked CANCELLED after ${chunkIndex} chunks, ${totalLoaded} pts, ${(performance.now()-t0).toFixed(1)}ms`);
            return { cancelled: true };
        }

        const nPts = result.buffer ? result.buffer.byteLength / 16 : 0;
        let tGpu = tWasm;
        if (nPts > 0) {
            state.gpu.appendDataPointsFromBuffer(result.buffer, options);
            tGpu = performance.now();
            totalLoaded += nPts;
        }

        console.log(`[GGRS-V2 timing] chunk[${chunkIndex}]: ${nPts} pts  wasm=${(tWasm-tChunk).toFixed(1)}ms  gpu=${(tGpu-tWasm).toFixed(1)}ms  total=${(tGpu-tChunk).toFixed(1)}ms  cumPts=${totalLoaded}`);

        if (result.done) {
            const elapsed = performance.now() - t0;
            console.log(`[GGRS-V2 timing] streamAllDataPacked DONE  ${chunkIndex+1} chunks, ${totalLoaded} pts, ${elapsed.toFixed(1)}ms  (${totalLoaded > 0 ? (totalLoaded / elapsed * 1000).toFixed(0) : 0} pts/s)`);
            return { cancelled: false, loaded: totalLoaded };
        }

        const tFrame = performance.now();
        await new Promise(resolve => requestAnimationFrame(resolve));
        const tAfterFrame = performance.now();
        console.log(`[GGRS-V2 timing] chunk[${chunkIndex}] frame yield: ${(tAfterFrame-tFrame).toFixed(1)}ms`);

        chunkIndex++;
    }
}

/**
 * Cancel any in-flight streaming loop for a container.
 * Increments streamingToken so the running loop exits on next check.
 */
function ggrsV2CancelStreaming(containerId) {
    const state = _containers[containerId];
    if (state) state.streamingToken++;
}

// ─── Expose to window ──────────────────────────────────────────────────────────

// V2 GPU setup (idempotent)
window.ggrsV2EnsureGpu = ggrsV2EnsureGpu;
window.ggrsV2SetupGpu = ggrsV2EnsureGpu;  // backward compat alias
window.ggrsV2SetPanelLayout = ggrsV2SetPanelLayout;
window.ggrsV2MergeAndSetChrome = ggrsV2MergeAndSetChrome;

// V2 data streaming
window.ggrsV2AppendDataPoints = ggrsV2AppendDataPoints;
window.ggrsV2ClearDataPoints = ggrsV2ClearDataPoints;
window.ggrsV2LoadDataChunk = ggrsV2LoadDataChunk;
window.ggrsV2StreamAllData = ggrsV2StreamAllData;
window.ggrsV2StreamAllDataPacked = ggrsV2StreamAllDataPacked;
window.ggrsV2CancelStreaming = ggrsV2CancelStreaming;

// V2 interaction
window.ggrsV2AttachInteraction = ggrsV2AttachInteraction;

// V2 init view state in WASM (called from Dart after skeleton + initPlotStream)
// Also stores renderer ref in container state for subsequent calls.
window.ggrsV2InitView = function(containerId, renderer, paramsJson) {
    const state = _containers[containerId];
    if (!state) {
        throw new Error('[GGRS-V2] Cannot initView: container not initialized: ' + containerId);
    }
    state.renderer = renderer;
    const snapshot = JSON.parse(renderer.initView(paramsJson));
    return snapshot;
};

// V2 get view chrome from WASM ViewState (called from Dart for initial chrome)
window.ggrsV2GetViewChrome = function(containerId) {
    const state = _containers[containerId];
    if (!state || !state.renderer) {
        throw new Error('[GGRS-V2] Cannot getViewChrome: container not ready: ' + containerId);
    }
    const json = state.renderer.getViewChrome();
    return JSON.parse(json);
};

// V3 set chrome from WASM merged getViewChrome (called from Dart on initial render)
window.ggrsV2SetChrome = function(containerId) {
    _rebuildViewChrome(containerId);
};

// V2/V3 programmatic zoom (called from Dart for Flutter drop zones outside GGRS)
// direction: 'width', 'height', or 'both'. sign: 1 = zoom in, -1 = zoom out.
// Anchor is always data origin (handled in WASM).
window.ggrsV2Zoom = function(containerId, direction, sign) {
    const state = _containers[containerId];
    if (!state || !state.gpu || !state.renderer) {
        throw new Error('[GGRS-V2] Cannot zoom: container not ready: ' + containerId);
    }
    const axis = direction === 'width' ? 'x' : direction === 'height' ? 'y' : 'both';
    const snapshot = JSON.parse(state.renderer.zoom(axis, sign));
    // Apply full snapshot (both shaders)
    state.gpu.setAxisRange(snapshot.vis_x_min, snapshot.vis_x_max,
                           snapshot.vis_y_min, snapshot.vis_y_max);
    state.gpu.setCellSize(snapshot.cell_width, snapshot.cell_height);
    state.gpu.setVisibleCounts(snapshot.n_visible_cols, snapshot.n_visible_rows);
    state.gpu.setFacetViewport(snapshot.viewport_col_start, snapshot.viewport_row_start);
    state.gpu.setScrollOffset(snapshot.scroll_offset_x, snapshot.scroll_offset_y);
    state.gpu.setRectScroll(snapshot.scroll_x, snapshot.scroll_y);
    state.scrollX = snapshot.scroll_x;
    state.scrollY = snapshot.scroll_y;
    _rebuildViewChrome(containerId);
};

// V2 cleanup
window.ggrsV2ClearAll = ggrsV2ClearAll;
