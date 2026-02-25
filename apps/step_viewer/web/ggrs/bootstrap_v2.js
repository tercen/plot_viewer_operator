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

function _drawTextsOnCanvas(canvas, texts, dpr) {
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
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
    return [0.5, 0.5, 0.5, 1.0];  // gray fallback for unrecognized
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

    // Clear and redraw
    _drawTextsOnCanvas(canvas, textPlacements || [], dpr);
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
        chromeStyle: null,        // cached from mergeAndSetChrome
        scrollOffsetX: 0,
        scrollOffsetY: 0,
        streamingToken: 0,
    };

    // Update plot_background clear color
    gpu._clearColor = { r: 1, g: 1, b: 1, a: 1 };
}

/**
 * Set panel layout — writes full 80-byte view uniform.
 * Called after initPlotStream when panel dimensions are known.
 * Stores initial cell sizes for double-click reset.
 */
function ggrsV2SetPanelLayout(containerId, params) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);

    state.panelLayout = { ...params };
    state.panelLayout.initialCellWidth = params.cellWidth;
    state.panelLayout.initialCellHeight = params.cellHeight;
    state.gpu.setViewUniforms(params);
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
    const labelTexts = [];
    if (staticChrome.title) labelTexts.push(staticChrome.title);
    if (staticChrome.x_label) labelTexts.push(staticChrome.x_label);
    if (staticChrome.y_label) labelTexts.push(staticChrome.y_label);
    for (const sl of staticChrome.strip_labels || []) labelTexts.push(sl);
    for (const sl of vpChrome.strip_labels || []) labelTexts.push(sl);
    _setTextLayer(containerId, 'labels', labelTexts);

    const tickTexts = [
        ...(staticChrome.x_ticks || []), ...(vpChrome.x_ticks || []),
        ...(staticChrome.y_ticks || []), ...(vpChrome.y_ticks || []),
    ];
    _setTextLayer(containerId, 'ticks', tickTexts);

    // Cache style info for zoom chrome rebuilds
    state.chromeStyle = {
        panelFill: vpChrome.panel_backgrounds?.[0]?.fill || '#FFFFFF',
        borderColor: vpChrome.panel_borders?.[0]?.color || '#D1D5DB',
        borderWidth: vpChrome.panel_borders?.[0]?.stroke_width || 1,
    };
}

/**
 * Compute ticks for a given axis range using WASM.
 * Sync, <1ms. Returns { x_breaks, x_labels, y_breaks, y_labels }.
 */
function _computeTicks(renderer, xMin, xMax, yMin, yMax) {
    const json = renderer.computeTicksForRange(xMin, xMax, yMin, yMax);
    const result = JSON.parse(json);
    if (result.error) {
        throw new Error('[GGRS-V2] computeTicksForRange failed: ' + result.error);
    }
    return result;
}

/**
 * Rebuild all geometric chrome layers from current layout params.
 * Called on debounce after zoom changes cell size.
 * Does NOT touch the 'labels' text layer (title, axis labels, strip labels).
 */
function _rebuildChromeForZoom(containerId) {
    const state = _containers[containerId];
    if (!state || !state.panelLayout || !state.renderer) return;

    const gpu = state.gpu;
    const layout = state.panelLayout;
    const style = state.chromeStyle || {};

    const originX = layout.gridOriginX;
    const originY = layout.gridOriginY;
    const cellW = gpu.cellWidth;
    const cellH = gpu.cellHeight;
    const spacing = layout.cellSpacing;
    const nCols = layout.nActualCols || 1;
    const nRows = layout.nActualRows || 1;

    const totalW = nCols * cellW + Math.max(0, nCols - 1) * spacing;
    const totalH = nRows * cellH + Math.max(0, nRows - 1) * spacing;

    const xMin = gpu.xMin, xMax = gpu.xMax;
    const yMin = gpu.yMin, yMax = gpu.yMax;
    const xSpan = xMax - xMin;
    const ySpan = yMax - yMin;

    const ticks = _computeTicks(state.renderer, xMin, xMax, yMin, yMax);

    // ── Panel backgrounds ──
    const panelFill = _parseColor(style.panelFill || '#FFFFFF');
    const bgRects = [];
    for (let c = 0; c < nCols; c++) {
        for (let r = 0; r < nRows; r++) {
            bgRects.push({
                x: originX + c * (cellW + spacing),
                y: originY + r * (cellH + spacing),
                width: cellW, height: cellH, color: panelFill,
            });
        }
    }
    gpu.setLayer('panel_backgrounds', bgRects);

    // ── Grid lines (skip when cells too small to see) ──
    const gridRects = [];
    if (cellW > 5 || cellH > 5) {
        const gc = _parseColor('#E5E7EB');
        for (let c = 0; c < nCols; c++) {
            for (let r = 0; r < nRows; r++) {
                const px = originX + c * (cellW + spacing);
                const py = originY + r * (cellH + spacing);
                if (cellW > 5 && xSpan > 1e-15) {
                    for (const xb of ticks.x_breaks) {
                        const nx = (xb - xMin) / xSpan;
                        if (nx >= 0 && nx <= 1) {
                            gridRects.push({ x: px + nx * cellW - 0.5, y: py, width: 1, height: cellH, color: gc });
                        }
                    }
                }
                if (cellH > 5 && ySpan > 1e-15) {
                    for (const yb of ticks.y_breaks) {
                        const ny = (yb - yMin) / ySpan;
                        if (ny >= 0 && ny <= 1) {
                            gridRects.push({ x: px, y: py + (1 - ny) * cellH - 0.5, width: cellW, height: 1, color: gc });
                        }
                    }
                }
            }
        }
    }
    gpu.setLayer('grid_lines', gridRects);

    // ── Axis lines ──
    const ac = _parseColor('#374151');
    gpu.setLayer('axis_lines', [
        { x: originX, y: originY + totalH, width: totalW, height: 1, color: ac },
        { x: originX - 1, y: originY, width: 1, height: totalH, color: ac },
    ]);

    // ── Tick marks (bottom row for X, left column for Y — same as WASM) ──
    const tickRects = [];
    // X tick marks: bottom of each cell in the last row only
    if (xSpan > 1e-15) {
        const bottomRow = nRows - 1;
        for (let c = 0; c < nCols; c++) {
            const px = originX + c * (cellW + spacing);
            const py = originY + bottomRow * (cellH + spacing);
            for (const xb of ticks.x_breaks) {
                const nx = (xb - xMin) / xSpan;
                if (nx >= 0 && nx <= 1) {
                    tickRects.push({ x: px + nx * cellW - 0.5, y: py + cellH, width: 1, height: 5, color: ac });
                }
            }
        }
    }
    // Y tick marks: left of each cell in the first column only
    if (ySpan > 1e-15 && cellH >= 20) {
        for (let r = 0; r < nRows; r++) {
            const py = originY + r * (cellH + spacing);
            for (const yb of ticks.y_breaks) {
                const ny = (yb - yMin) / ySpan;
                if (ny >= 0 && ny <= 1) {
                    tickRects.push({ x: originX - 5, y: py + (1 - ny) * cellH - 0.5, width: 5, height: 1, color: ac });
                }
            }
        }
    }
    gpu.setLayer('tick_marks', tickRects);

    // ── Panel borders ──
    const bc = _parseColor(style.borderColor || '#D1D5DB');
    const bw = style.borderWidth || 1;
    const borderRects = [];
    for (let c = 0; c < nCols; c++) {
        for (let r = 0; r < nRows; r++) {
            const px = originX + c * (cellW + spacing);
            const py = originY + r * (cellH + spacing);
            borderRects.push({ x: px, y: py, width: cellW, height: bw, color: bc });
            borderRects.push({ x: px, y: py + cellH - bw, width: cellW, height: bw, color: bc });
            borderRects.push({ x: px, y: py + bw, width: bw, height: cellH - 2 * bw, color: bc });
            borderRects.push({ x: px + cellW - bw, y: py + bw, width: bw, height: cellH - 2 * bw, color: bc });
        }
    }
    gpu.setLayer('panel_borders', borderRects);

    // ── Tick labels (bottom row for X, left column for Y — same as WASM) ──
    const tickTexts = [];
    // X tick labels: below the last row only
    if (xSpan > 1e-15) {
        const bottomRow = nRows - 1;
        for (let c = 0; c < nCols; c++) {
            const px = originX + c * (cellW + spacing);
            const py = originY + bottomRow * (cellH + spacing);
            for (let i = 0; i < ticks.x_breaks.length; i++) {
                const nx = (ticks.x_breaks[i] - xMin) / xSpan;
                if (nx >= -0.05 && nx <= 1.05) {
                    tickTexts.push({
                        text: ticks.x_labels[i],
                        x: px + nx * cellW, y: py + cellH + 12,
                        font_size: 11, font_family: 'Fira Sans, sans-serif',
                        font_weight: 'normal', color: '#374151',
                        anchor: 'middle', baseline: 'auto',
                    });
                }
            }
        }
    }
    // Y tick labels: left of first column only, when cell tall enough
    if (ySpan > 1e-15 && cellH >= 20) {
        for (let r = 0; r < nRows; r++) {
            const py = originY + r * (cellH + spacing);
            for (let i = 0; i < ticks.y_breaks.length; i++) {
                const ny = (ticks.y_breaks[i] - yMin) / ySpan;
                if (ny >= -0.05 && ny <= 1.05) {
                    tickTexts.push({
                        text: ticks.y_labels[i],
                        x: originX - 8, y: py + (1 - ny) * cellH,
                        font_size: 11, font_family: 'Fira Sans, sans-serif',
                        font_weight: 'normal', color: '#374151',
                        anchor: 'end', baseline: 'central',
                    });
                }
            }
        }
    }
    _setTextLayer(containerId, 'ticks', tickTexts);

    gpu.requestRedraw();
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
 * Attach zoom interaction. Attach-once: if already attached, just update
 * the renderer ref (no handler re-creation).
 *
 * Zoom = mouse wheel changes cell height. Shift+wheel changes cell width.
 * Double-click resets to initial cell size.
 *
 * @param {string} containerId
 * @param {Object} renderer - WASM GGRSRenderer (for computeTicksForRange)
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
    let rebuildTimer = null;

    function scheduleRebuild() {
        clearTimeout(rebuildTimer);
        rebuildTimer = setTimeout(() => _rebuildChromeForZoom(containerId), 6);
    }

    // ── Facet zoom: wheel ──────────────────────────────────────────────────

    function onWheel(e) {
        e.preventDefault();
        const sign = e.deltaY < 0 ? 1 : -1;  // scroll up = zoom in = bigger

        const oldW = gpu.cellWidth;
        const oldH = gpu.cellHeight;

        if (e.shiftKey) {
            // Shift+wheel → cell width (X zoom)
            const step = Math.max(1, Math.sqrt(gpu.cellWidth));
            const newW = Math.max(0.001, gpu.cellWidth + step * sign);
            gpu.setCellSize(newW, gpu.cellHeight);
            state.panelLayout.cellWidth = newW;
            console.log('[ZOOM] shift+wheel deltaY=' + e.deltaY + ' sign=' + sign + ' oldW=' + oldW.toFixed(3) + ' step=' + step.toFixed(3) + ' newW=' + newW.toFixed(3));
        } else {
            // Wheel → cell height (Y zoom)
            const step = Math.max(1, Math.sqrt(gpu.cellHeight));
            const newH = Math.max(0.001, gpu.cellHeight + step * sign);
            gpu.setCellSize(gpu.cellWidth, newH);
            state.panelLayout.cellHeight = newH;
            console.log('[ZOOM] wheel deltaY=' + e.deltaY + ' sign=' + sign + ' oldH=' + oldH.toFixed(3) + ' step=' + step.toFixed(3) + ' newH=' + newH.toFixed(3));
        }

        scheduleRebuild();
    }

    // ── Double-click: reset cell size ──────────────────────────────────────

    function onDblClick() {
        if (state.panelLayout) {
            const layout = state.panelLayout;
            gpu.setCellSize(layout.initialCellWidth, layout.initialCellHeight);
            layout.cellWidth = layout.initialCellWidth;
            layout.cellHeight = layout.initialCellHeight;
            scheduleRebuild();
        }
    }

    interactionDiv.addEventListener('wheel', onWheel, { passive: false });
    interactionDiv.addEventListener('dblclick', onDblClick);

    state.interactionCleanup = () => {
        interactionDiv.removeEventListener('wheel', onWheel);
        interactionDiv.removeEventListener('dblclick', onDblClick);
        clearTimeout(rebuildTimer);
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

    let totalLoaded = 0;
    while (true) {
        if (state.streamingToken !== token) return { cancelled: true };

        const json = await renderer.loadDataChunk(chunkSize);
        const result = JSON.parse(json);
        if (result.error) throw new Error('[GGRS-V2] loadDataChunk: ' + result.error);

        if (state.streamingToken !== token) return { cancelled: true };

        if (result.points && result.points.length > 0) {
            state.gpu.appendDataPoints(result.points, options);
            totalLoaded += result.points.length;
        }

        if (result.done) return { cancelled: false, loaded: totalLoaded };

        await new Promise(resolve => requestAnimationFrame(resolve));
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
window.ggrsV2CancelStreaming = ggrsV2CancelStreaming;

// V2 interaction
window.ggrsV2AttachInteraction = ggrsV2AttachInteraction;

// V2 scroll / facet viewport
window.ggrsV2SetScrollOffset = function(containerId, dx, dy) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);
    state.gpu.setScrollOffset(dx, dy);
};
window.ggrsV2SetFacetViewport = function(containerId, colStart, rowStart) {
    const state = _containers[containerId];
    if (!state) throw new Error('[GGRS-V2] Not initialized: ' + containerId);
    state.gpu.setFacetViewport(colStart, rowStart);
};

// V2 cleanup
window.ggrsV2ClearAll = ggrsV2ClearAll;
