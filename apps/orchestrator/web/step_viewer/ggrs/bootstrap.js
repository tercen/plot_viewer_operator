/* DEPRECATED: This file has been replaced by bootstrap_v3.js
 * All code below is commented out and should not be used.
 * Date: 2026-03-03
 */

/*
import init, { GGRSRenderer } from "./pkg/ggrs_wasm.js";
import { GgrsGpuRenderer } from "./ggrs_gpu.js";

// Global WASM initialization state
let wasmInitialized = false;
let wasmInitPromise = null;

/**
 * Ensure WASM is initialized (idempotent - only initializes once)
 * @returns {Promise<void>}
 */
function ensureWasmInitialized() {
    if (wasmInitialized) {
        return Promise.resolve();
    }

    if (wasmInitPromise) {
        return wasmInitPromise;
    }

    console.log('[GGRS] Starting WASM initialization...');
    wasmInitPromise = init()
        .then(() => {
            wasmInitialized = true;
            console.log('[GGRS] WASM initialized successfully');
        })
        .catch((e) => {
            console.error('[GGRS] WASM initialization failed:', e);
            wasmInitPromise = null; // Allow retry
            throw e;
        });

    return wasmInitPromise;
}

/**
 * Create a new GGRS renderer instance
 * Must be called after WASM is initialized
 * @param {string} canvasId - Canvas element ID
 * @returns {GGRSRenderer}
 */
function createGGRSRenderer(canvasId) {
    if (!wasmInitialized) {
        throw new Error('WASM not initialized. Call ensureWasmInitialized() first.');
    }

    console.log('[GGRS] Creating renderer for canvas:', canvasId);
    const renderer = new GGRSRenderer(canvasId);
    console.log('[GGRS] Renderer created successfully');
    return renderer;
}

/**
 * Create a browser-based text measurer using a hidden canvas.
 * Returns a function(text, fontFamily, fontSizePx) -> [width, height]
 *
 * @returns {Function} Text measurement callback
 */
function ggrsCreateTextMeasurer() {
    const canvas = document.createElement('canvas');
    canvas.width = 1;
    canvas.height = 1;
    const ctx = canvas.getContext('2d');

    return function measureText(text, fontFamily, fontSizePx) {
        ctx.font = `${fontSizePx}px ${fontFamily}`;
        const metrics = ctx.measureText(text);
        const width = metrics.width;
        const height = (metrics.fontBoundingBoxAscent !== undefined &&
                        metrics.fontBoundingBoxDescent !== undefined)
            ? metrics.fontBoundingBoxAscent + metrics.fontBoundingBoxDescent
            : fontSizePx * 1.2;
        return [width, height];
    };
}

/**
 * Compute layout information for interactive rendering.
 *
 * @param {GGRSRenderer} renderer - GGRS renderer instance
 * @param {string} dataJson - TercenDataPayload as JSON string
 * @param {number} width - Canvas width in pixels
 * @param {number} height - Canvas height in pixels
 * @param {Function|null} [measureTextFn=null] - Optional JS text measurement callback
 * @returns {Object} Parsed LayoutInfo
 */
function ggrsComputeLayout(renderer, dataJson, width, height, measureTextFn) {
    let json;
    if (measureTextFn) {
        json = renderer.computeLayoutWithMeasurer(dataJson, width, height, measureTextFn);
    } else {
        json = renderer.computeLayout(dataJson, width, height);
    }
    const layoutInfo = JSON.parse(json);
    if (layoutInfo.error) {
        throw new Error('[GGRS] computeLayout failed: ' + layoutInfo.error);
    }
    return layoutInfo;
}

/**
 * Render chrome (SVG + DOM text) from a LayoutInfo object into a container.
 *
 * Creates or updates the 6-layer DOM structure:
 *   Layer 0: <canvas class="ggrs-background">  (plot bg + panel/strip backgrounds)
 *   Layer 1: <svg class="ggrs-chrome">          (grid, axes, ticks, panel borders)
 *   Layer 2: <canvas class="ggrs-data">         (data points — above chrome)
 *   Layer 3: <div class="ggrs-text">            (tick labels, axis labels, titles)
 *   Layer 4: <svg class="ggrs-annotations">     (user annotations)
 *   Layer 5: <div class="ggrs-interaction">     (mouse/touch handling)
 *
 * @param {string} containerId - DOM container element ID
 * @param {Object} layoutInfo - Parsed LayoutInfo from ggrsComputeLayout
 */
function ggrsRenderChrome(containerId, layoutInfo) {
    const container = document.getElementById(containerId);
    if (!container) {
        throw new Error('[GGRS] Container not found: ' + containerId);
    }

    const w = layoutInfo.width;
    const h = layoutInfo.height;

    container.style.position = 'relative';
    container.style.width = w + 'px';
    container.style.height = h + 'px';
    container.style.overflow = 'hidden';

    // Destroy GPU renderer if it exists (Phase 1 replaces Phase 3 DOM)
    if (container._ggrsGpu) {
        container._ggrsGpu.destroy();
        container._ggrsGpu = null;
    }

    // Clear previous content
    container.innerHTML = '';

    const dpr = window.devicePixelRatio || 1;

    // Layer 0: Background canvas (plot background + panel/strip backgrounds)
    const bgCanvas = document.createElement('canvas');
    bgCanvas.className = 'ggrs-background';
    bgCanvas.width = w * dpr;
    bgCanvas.height = h * dpr;
    _applyLayerStyle(bgCanvas, w, h);
    container.appendChild(bgCanvas);

    const bgCtx = bgCanvas.getContext('2d');
    bgCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (layoutInfo.plot_background) {
        bgCtx.fillStyle = layoutInfo.plot_background;
        bgCtx.fillRect(0, 0, w, h);
    }
    for (const bg of layoutInfo.panel_backgrounds || []) {
        bgCtx.fillStyle = bg.fill;
        bgCtx.fillRect(bg.x, bg.y, bg.width, bg.height);
    }
    for (const sb of layoutInfo.strip_backgrounds || []) {
        bgCtx.fillStyle = sb.fill;
        bgCtx.fillRect(sb.x, sb.y, sb.width, sb.height);
    }

    // Layer 1: SVG chrome (grid, axes, ticks, panel borders — no filled backgrounds)
    const chromeSvg = _createSvgElement('svg', {
        width: w, height: h,
        viewBox: `0 0 ${w} ${h}`,
        class: 'ggrs-chrome'
    });
    _applyLayerStyle(chromeSvg, w, h);

    for (const gl of layoutInfo.grid_lines || []) {
        chromeSvg.appendChild(_createSvgElement('line', {
            x1: gl.x1, y1: gl.y1, x2: gl.x2, y2: gl.y2,
            stroke: gl.color, 'stroke-width': gl.width
        }));
    }

    for (const al of layoutInfo.axis_lines || []) {
        chromeSvg.appendChild(_createSvgElement('line', {
            x1: al.x1, y1: al.y1, x2: al.x2, y2: al.y2,
            stroke: al.color, 'stroke-width': al.width
        }));
    }

    for (const tm of layoutInfo.tick_marks || []) {
        chromeSvg.appendChild(_createSvgElement('line', {
            x1: tm.x1, y1: tm.y1, x2: tm.x2, y2: tm.y2,
            stroke: tm.color, 'stroke-width': tm.width
        }));
    }

    for (const pb of layoutInfo.panel_borders || []) {
        chromeSvg.appendChild(_createSvgElement('rect', {
            x: pb.x, y: pb.y, width: pb.width, height: pb.height,
            fill: 'none', stroke: pb.color, 'stroke-width': pb.stroke_width
        }));
    }

    container.appendChild(chromeSvg);

    // Layer 2: Data canvas (above SVG chrome so data points are visible)
    const dataCanvas = document.createElement('canvas');
    dataCanvas.className = 'ggrs-data';
    dataCanvas.width = w * dpr;
    dataCanvas.height = h * dpr;
    _applyLayerStyle(dataCanvas, w, h);
    container.appendChild(dataCanvas);

    // Layer 3: DOM text
    const textDiv = document.createElement('div');
    textDiv.className = 'ggrs-text';
    _applyLayerStyle(textDiv, w, h);

    const allTexts = [
        ...(layoutInfo.x_ticks || []),
        ...(layoutInfo.y_ticks || []),
        ...(layoutInfo.strip_labels || []),
    ];
    if (layoutInfo.title) allTexts.push(layoutInfo.title);
    if (layoutInfo.x_label) allTexts.push(layoutInfo.x_label);
    if (layoutInfo.y_label) allTexts.push(layoutInfo.y_label);

    for (const tp of allTexts) {
        textDiv.appendChild(_createTextSpan(tp));
    }

    container.appendChild(textDiv);

    // Layer 4: SVG annotations (empty)
    const annotationsSvg = _createSvgElement('svg', {
        width: w, height: h,
        viewBox: `0 0 ${w} ${h}`,
        class: 'ggrs-annotations'
    });
    _applyLayerStyle(annotationsSvg, w, h);
    container.appendChild(annotationsSvg);

    // Layer 5: Interaction div (empty)
    const interactionDiv = document.createElement('div');
    interactionDiv.className = 'ggrs-interaction';
    _applyLayerStyle(interactionDiv, w, h);
    container.appendChild(interactionDiv);
}

/**
 * Render data points — GPU path (WebGPU) or Canvas 2D fallback (Phase 1 SVG chrome).
 *
 * @param {string} containerId - DOM container element ID
 * @param {Array} points - Array of {panel_idx, px, py} from loadAndMapChunk
 * @param {Object} options - Rendering options {radius, fillColor, opacity}
 */
function ggrsRenderDataPoints(containerId, points, options) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // GPU path: WebGPU renderer exists
    const gpu = container._ggrsGpu;
    if (gpu) {
        // Route to split-buffer path if active, else legacy path
        if (gpu._staticChrome || gpu._viewportChrome) {
            gpu.appendViewportPoints(points, options);
        } else {
            gpu.appendDataPoints(points, options);
        }
        gpu.requestRedraw();
        return;
    }

    // Canvas 2D path: SVG chrome layers (Phase 1)
    const canvas = container.querySelector('.ggrs-data');
    if (!canvas) return;

    const dpr = window.devicePixelRatio || 1;
    const ctx = canvas.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const r = (options && options.radius) || 2.5;
    const color = (options && options.fillColor) || 'rgba(0,0,0,0.6)';

    ctx.fillStyle = color;
    ctx.beginPath();
    for (const pt of points) {
        ctx.moveTo(pt.px + r, pt.py);
        ctx.arc(pt.px, pt.py, r, 0, Math.PI * 2);
    }
    ctx.fill();
}

// Internal helpers

const SVG_NS = 'http://www.w3.org/2000/svg';

function _createSvgElement(tag, attrs) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const [key, value] of Object.entries(attrs)) {
        el.setAttribute(key, String(value));
    }
    return el;
}

function _applyLayerStyle(el, w, h) {
    el.style.position = 'absolute';
    el.style.left = '0';
    el.style.top = '0';
    el.style.width = w + 'px';
    el.style.height = h + 'px';
    el.style.pointerEvents = 'none';
}

/**
 * Create the 6-layer DOM structure and render global chrome (plot background,
 * column strip backgrounds/labels, title, axis labels).
 *
 * Per-cell elements (panel backgrounds, grid lines, tick marks, axis lines,
 * panel borders, tick labels, row strip backgrounds/labels) are NOT rendered
 * here — use ggrsRenderChromeBatch() to render them incrementally.
 *
 * @param {string} containerId - DOM container element ID
 * @param {Object} layoutInfo - Parsed LayoutInfo from getStreamLayout
 */
function ggrsCreateChromeLayers(containerId, layoutInfo) {
    const container = document.getElementById(containerId);
    if (!container) {
        throw new Error('[GGRS] Container not found: ' + containerId);
    }

    const w = layoutInfo.width;
    const h = layoutInfo.height;

    container.style.position = 'relative';
    container.style.width = w + 'px';
    container.style.height = h + 'px';
    container.style.overflow = 'hidden';

    // Destroy GPU renderer if switching back to SVG chrome layers
    if (container._ggrsGpu) {
        container._ggrsGpu.destroy();
        container._ggrsGpu = null;
    }

    // Clear previous content
    container.innerHTML = '';

    const dpr = window.devicePixelRatio || 1;

    // Layer 0: Background canvas
    const bgCanvas = document.createElement('canvas');
    bgCanvas.className = 'ggrs-background';
    bgCanvas.width = w * dpr;
    bgCanvas.height = h * dpr;
    _applyLayerStyle(bgCanvas, w, h);
    container.appendChild(bgCanvas);

    const bgCtx = bgCanvas.getContext('2d');
    bgCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (layoutInfo.plot_background) {
        bgCtx.fillStyle = layoutInfo.plot_background;
        bgCtx.fillRect(0, 0, w, h);
    }
    // Render column strip backgrounds (panel_idx absent = global)
    for (const sb of layoutInfo.strip_backgrounds || []) {
        if (sb.panel_idx === undefined || sb.panel_idx === null) {
            bgCtx.fillStyle = sb.fill;
            bgCtx.fillRect(sb.x, sb.y, sb.width, sb.height);
        }
    }

    // Layer 1: SVG chrome (empty — batches will append)
    const chromeSvg = _createSvgElement('svg', {
        width: w, height: h,
        viewBox: `0 0 ${w} ${h}`,
        class: 'ggrs-chrome'
    });
    _applyLayerStyle(chromeSvg, w, h);
    container.appendChild(chromeSvg);

    // Layer 2: Data canvas
    const dataCanvas = document.createElement('canvas');
    dataCanvas.className = 'ggrs-data';
    dataCanvas.width = w * dpr;
    dataCanvas.height = h * dpr;
    _applyLayerStyle(dataCanvas, w, h);
    container.appendChild(dataCanvas);

    // Layer 3: DOM text
    const textDiv = document.createElement('div');
    textDiv.className = 'ggrs-text';
    _applyLayerStyle(textDiv, w, h);
    container.appendChild(textDiv);

    // Render global text: title, axis labels, column strip labels
    const globalTexts = [];
    if (layoutInfo.title) globalTexts.push(layoutInfo.title);
    if (layoutInfo.x_label) globalTexts.push(layoutInfo.x_label);
    if (layoutInfo.y_label) globalTexts.push(layoutInfo.y_label);
    for (const sl of layoutInfo.strip_labels || []) {
        if (sl.panel_idx === undefined || sl.panel_idx === null) {
            globalTexts.push(sl);
        }
    }
    for (const tp of globalTexts) {
        textDiv.appendChild(_createTextSpan(tp));
    }

    // Layer 4: SVG annotations (empty)
    const annotationsSvg = _createSvgElement('svg', {
        width: w, height: h,
        viewBox: `0 0 ${w} ${h}`,
        class: 'ggrs-annotations'
    });
    _applyLayerStyle(annotationsSvg, w, h);
    container.appendChild(annotationsSvg);

    // Layer 5: Interaction div (empty)
    const interactionDiv = document.createElement('div');
    interactionDiv.className = 'ggrs-interaction';
    _applyLayerStyle(interactionDiv, w, h);
    container.appendChild(interactionDiv);
}

/**
 * Render chrome elements for a batch of panel cells [startCell, endCell).
 *
 * Appends to existing layers created by ggrsCreateChromeLayers().
 * Filters elements by panel_idx. Call repeatedly with increasing ranges
 * to progressively build chrome.
 *
 * @param {string} containerId - DOM container element ID
 * @param {Object} layoutInfo - Parsed LayoutInfo
 * @param {number} startCell - First panel index (inclusive)
 * @param {number} endCell - Last panel index (exclusive)
 */
function ggrsRenderChromeBatch(containerId, layoutInfo, startCell, endCell) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const inRange = (pi) => pi >= startCell && pi < endCell;

    const dpr = window.devicePixelRatio || 1;

    // Layer 0: Panel backgrounds + row strip backgrounds on background canvas
    const bgCanvas = container.querySelector('.ggrs-background');
    if (bgCanvas) {
        const bgCtx = bgCanvas.getContext('2d');
        bgCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
        for (const bg of layoutInfo.panel_backgrounds || []) {
            if (inRange(bg.panel_idx)) {
                bgCtx.fillStyle = bg.fill;
                bgCtx.fillRect(bg.x, bg.y, bg.width, bg.height);
            }
        }
        for (const sb of layoutInfo.strip_backgrounds || []) {
            if (sb.panel_idx !== undefined && sb.panel_idx !== null && inRange(sb.panel_idx)) {
                bgCtx.fillStyle = sb.fill;
                bgCtx.fillRect(sb.x, sb.y, sb.width, sb.height);
            }
        }
    }

    // Layer 1: Grid lines, axis lines, tick marks, panel borders on SVG chrome
    const chromeSvg = container.querySelector('.ggrs-chrome');
    if (chromeSvg) {
        for (const gl of layoutInfo.grid_lines || []) {
            if (inRange(gl.panel_idx)) {
                chromeSvg.appendChild(_createSvgElement('line', {
                    x1: gl.x1, y1: gl.y1, x2: gl.x2, y2: gl.y2,
                    stroke: gl.color, 'stroke-width': gl.width
                }));
            }
        }
        for (const al of layoutInfo.axis_lines || []) {
            if (inRange(al.panel_idx)) {
                chromeSvg.appendChild(_createSvgElement('line', {
                    x1: al.x1, y1: al.y1, x2: al.x2, y2: al.y2,
                    stroke: al.color, 'stroke-width': al.width
                }));
            }
        }
        for (const tm of layoutInfo.tick_marks || []) {
            if (inRange(tm.panel_idx)) {
                chromeSvg.appendChild(_createSvgElement('line', {
                    x1: tm.x1, y1: tm.y1, x2: tm.x2, y2: tm.y2,
                    stroke: tm.color, 'stroke-width': tm.width
                }));
            }
        }
        for (const pb of layoutInfo.panel_borders || []) {
            if (inRange(pb.panel_idx)) {
                chromeSvg.appendChild(_createSvgElement('rect', {
                    x: pb.x, y: pb.y, width: pb.width, height: pb.height,
                    fill: 'none', stroke: pb.color, 'stroke-width': pb.stroke_width
                }));
            }
        }
    }

    // Layer 3: Tick labels + row strip labels on text div
    const textDiv = container.querySelector('.ggrs-text');
    if (textDiv) {
        for (const tp of layoutInfo.x_ticks || []) {
            if (tp.panel_idx !== undefined && tp.panel_idx !== null && inRange(tp.panel_idx)) {
                textDiv.appendChild(_createTextSpan(tp));
            }
        }
        for (const tp of layoutInfo.y_ticks || []) {
            if (tp.panel_idx !== undefined && tp.panel_idx !== null && inRange(tp.panel_idx)) {
                textDiv.appendChild(_createTextSpan(tp));
            }
        }
        for (const tp of layoutInfo.strip_labels || []) {
            if (tp.panel_idx !== undefined && tp.panel_idx !== null && inRange(tp.panel_idx)) {
                textDiv.appendChild(_createTextSpan(tp));
            }
        }
    }
}

/**
 * Create a positioned text span from a TextPlacement object.
 * @param {Object} tp - TextPlacement
 * @returns {HTMLSpanElement}
 */
function _createTextSpan(tp) {
    const span = document.createElement('span');
    span.textContent = tp.text;
    span.style.position = 'absolute';
    span.style.left = tp.x + 'px';
    span.style.top = tp.y + 'px';
    span.style.fontSize = tp.font_size + 'px';
    span.style.fontFamily = tp.font_family;
    span.style.fontWeight = tp.font_weight || 'normal';
    span.style.color = tp.color;
    span.style.whiteSpace = 'nowrap';
    span.style.lineHeight = '1';
    span.style.pointerEvents = 'none';

    let transforms = [];

    if (tp.anchor === 'middle') {
        transforms.push('translateX(-50%)');
    } else if (tp.anchor === 'end') {
        transforms.push('translateX(-100%)');
    }

    if (tp.baseline === 'central') {
        transforms.push('translateY(-50%)');
    } else if (tp.baseline === 'auto') {
        transforms.push('translateY(-100%)');
    }

    if (tp.rotation && tp.rotation !== 0) {
        transforms.push(`rotate(${tp.rotation}deg)`);
    }

    if (transforms.length > 0) {
        span.style.transform = transforms.join(' ');
    }

    return span;
}

/**
 * Draw an array of TextPlacements on a canvas element.
 * @param {HTMLCanvasElement} canvas
 * @param {Array} texts - Array of TextPlacement objects
 * @param {number} dpr - Device pixel ratio
 */
function _drawTextsOnCanvas(canvas, texts, dpr) {
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    for (const tp of texts) {
        _drawTextPlacement(ctx, tp);
    }
}

/**
 * Clear just the data canvas (Layer 2) without rebuilding the DOM.
 *
 * Enables future progressive chrome updates without losing data,
 * or restarting data streaming after a chrome re-render.
 *
 * @param {string} containerId - DOM container element ID
 */
function ggrsClearDataCanvas(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;
    const canvas = container.querySelector('.ggrs-data');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
}

/**
 * Render chrome via WebGPU — backgrounds, lines, borders on GPU canvas;
 * text labels on a Canvas 2D overlay.
 *
 * Creates a 3-element DOM structure (first call only):
 *   <canvas class="ggrs-gpu">         — WebGPU: backgrounds, lines, borders, data points
 *   <canvas class="ggrs-text">        — Canvas 2D: text labels (transparent overlay)
 *   <div class="ggrs-interaction">    — mouse/touch handling
 *
 * Subsequent calls reuse existing GPU renderer — NO container.innerHTML clearing.
 * Returns a Promise (async on first call for GPU init, resolved immediately after).
 *
 * @param {string} containerId - DOM container element ID
 * @param {Object} layoutInfo - Parsed LayoutInfo from getStreamLayout or computeLayout
 * @returns {Promise<void>}
 */
async function ggrsRenderChromeCanvas(containerId, layoutInfo) {
    const container = document.getElementById(containerId);
    if (!container) {
        throw new Error('[GGRS] Container not found: ' + containerId);
    }

    const w = layoutInfo.width;
    const h = layoutInfo.height;
    const dpr = window.devicePixelRatio || 1;

    container.style.position = 'relative';
    container.style.width = w + 'px';
    container.style.height = h + 'px';
    container.style.overflow = 'hidden';

    let gpu = container._ggrsGpu;

    if (!gpu) {
        // First render: create DOM structure and init WebGPU
        container.innerHTML = '';

        // WebGPU canvas (replaces background + chrome + data layers)
        const gpuCanvas = document.createElement('canvas');
        gpuCanvas.className = 'ggrs-gpu';
        gpuCanvas.width = w * dpr;
        gpuCanvas.height = h * dpr;
        _applyLayerStyle(gpuCanvas, w, h);
        container.appendChild(gpuCanvas);

        // Text overlay canvas (Canvas 2D — transparent)
        const textCanvas = document.createElement('canvas');
        textCanvas.className = 'ggrs-text';
        textCanvas.width = w * dpr;
        textCanvas.height = h * dpr;
        _applyLayerStyle(textCanvas, w, h);
        container.appendChild(textCanvas);

        // Interaction div
        const interactionDiv = document.createElement('div');
        interactionDiv.className = 'ggrs-interaction';
        _applyLayerStyle(interactionDiv, w, h);
        container.appendChild(interactionDiv);

        gpu = new GgrsGpuRenderer();
        await gpu.init(gpuCanvas);
        container._ggrsGpu = gpu;
    } else {
        // Subsequent render: resize canvases if needed
        const gpuCanvas = container.querySelector('.ggrs-gpu');
        const textCanvas = container.querySelector('.ggrs-text');
        if (gpuCanvas && (gpuCanvas.width !== w * dpr || gpuCanvas.height !== h * dpr)) {
            gpuCanvas.width = w * dpr;
            gpuCanvas.height = h * dpr;
            _applyLayerStyle(gpuCanvas, w, h);
            // Reconfigure WebGPU context after canvas resize
            gpu._context.configure({
                device: gpu._device,
                format: gpu._format,
                alphaMode: 'opaque',
            });
        }
        if (textCanvas && (textCanvas.width !== w * dpr || textCanvas.height !== h * dpr)) {
            textCanvas.width = w * dpr;
            textCanvas.height = h * dpr;
            _applyLayerStyle(textCanvas, w, h);
        }
    }

    // Update canvas size uniform
    gpu.setCanvasSize(w, h);

    // Build chrome geometry on GPU
    gpu.setChromeGeometry(layoutInfo);

    // Collect text placements
    const allTexts = [
        ...(layoutInfo.x_ticks || []),
        ...(layoutInfo.y_ticks || []),
        ...(layoutInfo.strip_labels || []),
    ];
    if (layoutInfo.title) allTexts.push(layoutInfo.title);
    if (layoutInfo.x_label) allTexts.push(layoutInfo.x_label);
    if (layoutInfo.y_label) allTexts.push(layoutInfo.y_label);

    if (gpu._isStaging) {
        // Staging mode: defer text — old shifted text stays in sync with
        // old shifted GPU geometry until commitRender draws both atomically.
        gpu.pendingTexts = allTexts;
        gpu.pendingTextDpr = dpr;
    } else {
        // Direct mode (initial render): draw text immediately
        const textCanvas = container.querySelector('.ggrs-text');
        if (textCanvas) {
            _drawTextsOnCanvas(textCanvas, allTexts, dpr);
            textCanvas.style.transform = '';
        }
        gpu.pendingTexts = null;
    }

    gpu.requestRedraw();
}

/**
 * Draw a batch of lines, grouping consecutive lines with the same color+width.
 * @param {CanvasRenderingContext2D} ctx
 * @param {Array} lines - Array of {x1, y1, x2, y2, color, width}
 */
function _drawLineBatch(ctx, lines) {
    if (!lines || lines.length === 0) return;

    let currentColor = null;
    let currentWidth = null;

    ctx.beginPath();
    for (const ln of lines) {
        if (ln.color !== currentColor || ln.width !== currentWidth) {
            // Flush previous batch
            if (currentColor !== null) {
                ctx.stroke();
                ctx.beginPath();
            }
            currentColor = ln.color;
            currentWidth = ln.width;
            ctx.strokeStyle = currentColor;
            ctx.lineWidth = currentWidth;
        }
        ctx.moveTo(ln.x1, ln.y1);
        ctx.lineTo(ln.x2, ln.y2);
    }
    if (currentColor !== null) {
        ctx.stroke();
    }
}

/**
 * Draw a TextPlacement on a canvas context.
 * Maps anchor/baseline to canvas textAlign/textBaseline, handles rotation.
 * @param {CanvasRenderingContext2D} ctx
 * @param {Object} tp - TextPlacement { text, x, y, font_size, font_family, font_weight, color, anchor, baseline, rotation }
 */
function _drawTextPlacement(ctx, tp) {
    ctx.save();

    ctx.font = `${tp.font_weight || 'normal'} ${tp.font_size}px ${tp.font_family}`;
    ctx.fillStyle = tp.color;

    // Map anchor → textAlign
    switch (tp.anchor) {
        case 'middle': ctx.textAlign = 'center'; break;
        case 'end':    ctx.textAlign = 'right';  break;
        default:       ctx.textAlign = 'left';   break;
    }

    // Map baseline → textBaseline
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

/**
 * Initialize plot stream: discover domain tables, fetch metadata, create PlotGenerator.
 *
 * @param {GGRSRenderer} renderer - GGRS renderer instance
 * @param {string} configJson - InitConfig as JSON string
 * @returns {Promise<Object>} Parsed metadata { n_rows, n_col_facets, n_row_facets }
 */
async function ggrsInitPlotStream(renderer, configJson) {
    const resultJson = await renderer.initPlotStream(configJson);
    const result = JSON.parse(resultJson);
    if (result.error) {
        throw new Error('[GGRS] initPlotStream failed: ' + result.error);
    }
    return result;
}

/**
 * Compute layout from cached PlotGenerator (after initPlotStream).
 *
 * @param {GGRSRenderer} renderer - GGRS renderer instance
 * @param {number} width - Canvas width
 * @param {number} height - Canvas height
 * @param {string} viewportJson - Viewport filter JSON (empty string for none)
 * @param {Function} measureTextFn - Browser text measurement callback
 * @returns {Object} Parsed LayoutInfo
 */
function ggrsGetStreamLayout(renderer, width, height, viewportJson, measureTextFn) {
    const json = renderer.getStreamLayout(width, height, viewportJson, measureTextFn);
    const layoutInfo = JSON.parse(json);
    if (layoutInfo.error) {
        throw new Error('[GGRS] getStreamLayout failed: ' + layoutInfo.error);
    }
    return layoutInfo;
}

/**
 * Load a chunk of data, dequantize, pixel-map, cull, return visible points.
 *
 * @param {GGRSRenderer} renderer - GGRS renderer instance
 * @param {number} chunkSize - Number of rows to fetch
 * @returns {Promise<Object>} { points, done, loaded, total, stats }
 */
async function ggrsLoadAndMapChunk(renderer, chunkSize) {
    const resultJson = await renderer.loadAndMapChunk(chunkSize);
    const result = JSON.parse(resultJson);
    if (result.error) {
        throw new Error('[GGRS] loadAndMapChunk failed: ' + result.error);
    }
    return result;
}

/**
 * Attach viewport interaction handlers for smooth GPU-based zoom and pan.
 *
 * Handlers attach to the container div (not Layer 5), so they survive
 * chrome rebuilds that replace children.
 *
 * Plain wheel / Ctrl+wheel: zoom at cursor (scale *= exp(-deltaY * 0.002)).
 * Shift+wheel: horizontal-only zoom at cursor.
 * Mouse drag: pan (translate). Commits on mouseup.
 *
 * Visual feedback is instant (GPU uniform + CSS text transform).
 * Dart commit is debounced (200ms after last wheel, or on mouseup for pan).
 *
 * @param {string} containerId - DOM container element ID
 * @param {Function} onCommit - Callback(scale, panX, panY, originX, originY) when
 *   accumulated transform should be committed to a semantic re-render.
 */
function ggrsAttachViewportHandlers(containerId, onCommit) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // Don't attach duplicates
    if (container._ggrsViewportAttached) return;
    container._ggrsViewportAttached = true;

    // Accumulated transform state
    let scale = 1.0;
    let panX = 0;
    let panY = 0;
    // Zoom origin tracks the cursor position of the most recent zoom gesture.
    // Pan adjustments keep the cursor-point fixed when origin shifts.
    let originX = 0;
    let originY = 0;
    let commitTimer = null;

    /** Apply current accumulated transform to GPU + CSS text layers. */
    function applyVisual() {
        const gpu = container._ggrsGpu;
        if (!gpu) return;

        // Pre-compute combined translate: origin*(1-scale) + pan
        const tx = originX * (1 - scale) + panX;
        const ty = originY * (1 - scale) + panY;

        gpu.setViewTransform(scale, scale, tx, ty);

        // CSS transform on viewport text canvas to match GPU
        const vpTextCanvas = container.querySelector('.ggrs-text-viewport');
        if (vpTextCanvas) {
            vpTextCanvas.style.transform = `matrix(${scale}, 0, 0, ${scale}, ${tx}, ${ty})`;
        }
    }

    /** Schedule a commit (debounced 200ms). */
    function scheduleCommit() {
        if (commitTimer !== null) {
            clearTimeout(commitTimer);
        }
        commitTimer = setTimeout(doCommit, 200);
    }

    /** Fire the commit callback with accumulated transform, then reset. */
    function doCommit() {
        if (commitTimer !== null) {
            clearTimeout(commitTimer);
            commitTimer = null;
        }
        if (scale === 1.0 && panX === 0 && panY === 0) return;

        const s = scale, px = panX, py = panY, ox = originX, oy = originY;

        // Reset accumulated state
        scale = 1.0;
        panX = 0;
        panY = 0;
        originX = 0;
        originY = 0;

        // Do NOT reset GPU transform here — keep the zoomed visual while
        // Dart re-renders. Dart calls resetViewTransform() just before
        // writing new viewport chrome, so there's no visible gap.

        if (onCommit) {
            onCommit(s, px, py, ox, oy);
        }
    }

    // --- Wheel: zoom at cursor ---
    container.addEventListener('wheel', function(e) {
        e.preventDefault();

        const rect = container.getBoundingClientRect();
        const mouseX = e.clientX - rect.left;
        const mouseY = e.clientY - rect.top;

        // Smooth zoom factor from continuous deltaY
        const zoomFactor = Math.exp(-e.deltaY * 0.002);

        // Keep the point under the cursor fixed during zoom.
        // Before zoom: screenPt = pos * scale_old + tx_old
        // After zoom:  screenPt = pos * scale_new + tx_new (must be same)
        // So: tx_new = screenPt - pos * scale_new
        //   = screenPt - pos * scale_old * zoomFactor
        //   = screenPt * (1 - zoomFactor) + tx_old * zoomFactor
        const oldTx = originX * (1 - scale) + panX;
        const oldTy = originY * (1 - scale) + panY;

        scale *= zoomFactor;

        const newTx = mouseX * (1 - zoomFactor) + oldTx * zoomFactor;
        const newTy = mouseY * (1 - zoomFactor) + oldTy * zoomFactor;

        // Solve back for origin+pan: tx = origin*(1-scale) + pan
        // Set origin = mouseX (current cursor), solve for pan
        originX = mouseX;
        originY = mouseY;
        panX = newTx - mouseX * (1 - scale);
        panY = newTy - mouseY * (1 - scale);

        applyVisual();

        // Commit immediately if scale threshold exceeded
        if (scale > 2.0 || scale < 0.5) {
            doCommit();
        } else {
            scheduleCommit();
        }
    }, { passive: false });

    // --- Pan (mousedown + drag + mouseup) ---
    let panStart = null;
    let panStartPanX = 0;
    let panStartPanY = 0;

    container.addEventListener('mousedown', function(e) {
        panStart = { x: e.clientX, y: e.clientY };
        panStartPanX = panX;
        panStartPanY = panY;
        container.style.cursor = 'grabbing';
    });

    container.addEventListener('mousemove', function(e) {
        if (!panStart) return;
        e.preventDefault();

        panX = panStartPanX + (e.clientX - panStart.x);
        panY = panStartPanY + (e.clientY - panStart.y);
        applyVisual();
    });

    container.addEventListener('mouseup', function(e) {
        if (!panStart) return;
        panStart = null;
        container.style.cursor = '';

        // Commit on mouseup if any transform accumulated
        if (scale !== 1.0 || panX !== 0 || panY !== 0) {
            doCommit();
        }
    });

    container.addEventListener('mouseleave', function() {
        if (panStart) {
            panStart = null;
            container.style.cursor = '';
            // Commit accumulated transform on leave
            if (scale !== 1.0 || panX !== 0 || panY !== 0) {
                doCommit();
            }
        }
    });
}

/**
 * Set the view transform on the GPU renderer.
 * Applies scale + translate to all viewport geometry via uniform — sub-ms.
 * Also applies matching CSS transform to viewport text canvas.
 *
 * @param {string} containerId - DOM container element ID
 * @param {number} scale - Uniform scale factor
 * @param {number} tx - Combined translate X (originX*(1-scale) + panX)
 * @param {number} ty - Combined translate Y (originY*(1-scale) + panY)
 */
function ggrsSetViewTransform(containerId, scale, tx, ty) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const gpu = container._ggrsGpu;
    if (gpu) {
        gpu.setViewTransform(scale, scale, tx, ty);
    }

    // CSS transform on viewport text canvas to match GPU
    const vpTextCanvas = container.querySelector('.ggrs-text-viewport');
    if (vpTextCanvas) {
        vpTextCanvas.style.transform = `matrix(${scale}, 0, 0, ${scale}, ${tx}, ${ty})`;
    }
}

/**
 * Reset the view transform to identity on the GPU renderer.
 * Also resets CSS transform on viewport text canvas.
 *
 * @param {string} containerId - DOM container element ID
 */
function ggrsResetViewTransform(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const gpu = container._ggrsGpu;
    if (gpu) {
        gpu.resetViewTransform();
    }

    const vpTextCanvas = container.querySelector('.ggrs-text-viewport');
    if (vpTextCanvas) {
        vpTextCanvas.style.transform = '';
    }
}

/**
 * Enter staging mode on the GPU renderer.
 * Subsequent setChromeGeometry and appendDataPoints writes go to staging buffers.
 * Active buffers (currently displayed) remain untouched until commitRender.
 *
 * @param {string} containerId - DOM container element ID
 */
function ggrsBeginStaging(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const gpu = container._ggrsGpu;
    if (gpu) {
        gpu.beginStaging();
    }
}

/**
 * Commit staged render — atomically swap staging buffers to active,
 * draw deferred text, and reset scroll offset + CSS transform.
 * All three happen in the same synchronous JS task (before next paint).
 *
 * @param {string} containerId - DOM container element ID
 */
function ggrsCommitRender(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const gpu = container._ggrsGpu;
    if (!gpu) return;

    // 1. Swap GPU buffers (staging → active), reset scroll uniform to (0,0)
    gpu.commitStaging();

    // 2. Draw deferred text for the new viewport
    const textCanvas = container.querySelector('.ggrs-text');
    if (textCanvas && gpu.pendingTexts) {
        _drawTextsOnCanvas(textCanvas, gpu.pendingTexts, gpu.pendingTextDpr);
        gpu.pendingTexts = null;
    }

    // 3. Reset text CSS transform (was shifting old text to match old GPU offset)
    if (textCanvas) {
        textCanvas.style.transform = '';
    }

    // Split-buffer path: also reset viewport text canvas transform
    const vpTextCanvas = container.querySelector('.ggrs-text-viewport');
    if (vpTextCanvas) {
        vpTextCanvas.style.transform = '';
    }
}

// ─── Split-buffer API (Phase 1.2+) ──────────────────────────────────────────

/**
 * Collect all text placements from a layoutInfo.
 * Works for both static and viewport layout info.
 */
function _collectTexts(layoutInfo) {
    const texts = [
        ...(layoutInfo.x_ticks || []),
        ...(layoutInfo.y_ticks || []),
        ...(layoutInfo.strip_labels || []),
    ];
    if (layoutInfo.title) texts.push(layoutInfo.title);
    if (layoutInfo.x_label) texts.push(layoutInfo.x_label);
    if (layoutInfo.y_label) texts.push(layoutInfo.y_label);
    return texts;
}

/**
 * Ensure the split-buffer DOM structure exists.
 * Creates GPU canvas, static text canvas, viewport text canvas, interaction div.
 * Returns the GPU renderer (async on first call for GPU init).
 *
 * @param {string} containerId
 * @param {number} w - Logical width
 * @param {number} h - Logical height
 * @returns {Promise<{gpu: GgrsGpuRenderer, container: HTMLElement}>}
 */
async function _ensureSplitDom(containerId, w, h) {
    const container = document.getElementById(containerId);
    if (!container) throw new Error('[GGRS] Container not found: ' + containerId);

    const dpr = window.devicePixelRatio || 1;

    container.style.position = 'relative';
    container.style.width = w + 'px';
    container.style.height = h + 'px';
    container.style.overflow = 'hidden';

    let gpu = container._ggrsGpu;

    if (!gpu) {
        container.innerHTML = '';

        // WebGPU canvas (all geometry: static + viewport + points)
        const gpuCanvas = document.createElement('canvas');
        gpuCanvas.className = 'ggrs-gpu';
        gpuCanvas.width = w * dpr;
        gpuCanvas.height = h * dpr;
        _applyLayerStyle(gpuCanvas, w, h);
        container.appendChild(gpuCanvas);

        // Static text overlay (title, axis labels, column strip labels)
        const staticTextCanvas = document.createElement('canvas');
        staticTextCanvas.className = 'ggrs-text-static';
        staticTextCanvas.width = w * dpr;
        staticTextCanvas.height = h * dpr;
        _applyLayerStyle(staticTextCanvas, w, h);
        container.appendChild(staticTextCanvas);

        // Viewport text overlay (tick labels, row strip labels — CSS transformed on scroll)
        const vpTextCanvas = document.createElement('canvas');
        vpTextCanvas.className = 'ggrs-text-viewport';
        vpTextCanvas.width = w * dpr;
        vpTextCanvas.height = h * dpr;
        _applyLayerStyle(vpTextCanvas, w, h);
        container.appendChild(vpTextCanvas);

        // Interaction div
        const interactionDiv = document.createElement('div');
        interactionDiv.className = 'ggrs-interaction';
        _applyLayerStyle(interactionDiv, w, h);
        container.appendChild(interactionDiv);

        gpu = new GgrsGpuRenderer();
        await gpu.init(gpuCanvas);
        container._ggrsGpu = gpu;
    } else {
        // Resize if needed
        const gpuCanvas = container.querySelector('.ggrs-gpu');
        const staticTextCanvas = container.querySelector('.ggrs-text-static');
        const vpTextCanvas = container.querySelector('.ggrs-text-viewport');

        if (gpuCanvas && (gpuCanvas.width !== w * dpr || gpuCanvas.height !== h * dpr)) {
            gpuCanvas.width = w * dpr;
            gpuCanvas.height = h * dpr;
            _applyLayerStyle(gpuCanvas, w, h);
            gpu._context.configure({
                device: gpu._device,
                format: gpu._format,
                alphaMode: 'opaque',
            });
        }
        if (staticTextCanvas && (staticTextCanvas.width !== w * dpr || staticTextCanvas.height !== h * dpr)) {
            staticTextCanvas.width = w * dpr;
            staticTextCanvas.height = h * dpr;
            _applyLayerStyle(staticTextCanvas, w, h);
        }
        if (vpTextCanvas && (vpTextCanvas.width !== w * dpr || vpTextCanvas.height !== h * dpr)) {
            vpTextCanvas.width = w * dpr;
            vpTextCanvas.height = h * dpr;
            _applyLayerStyle(vpTextCanvas, w, h);
        }
    }

    gpu.setCanvasSize(w, h);
    return { gpu, container };
}

/**
 * Compute skeleton dimensions from cached PlotGenerator (after initPlotStream).
 * Caches PlotDimensions in WASM for subsequent getStaticChrome/getViewportChrome calls.
 *
 * @param {GGRSRenderer} renderer
 * @param {number} width
 * @param {number} height
 * @param {string} viewportJson - Viewport filter JSON (empty string for none)
 * @param {Function} measureTextFn - Browser text measurement callback
 * @returns {Object} Parsed skeleton { margins, panel_grid, width, height }
 */
function ggrsComputeSkeleton(renderer, width, height, viewportJson, measureTextFn) {
    const json = renderer.computeSkeleton(width, height, viewportJson, measureTextFn);
    const result = JSON.parse(json);
    if (result.error) {
        throw new Error('[GGRS] computeSkeleton failed: ' + result.error);
    }
    return result;
}

/**
 * Get static chrome layout (title, axis labels, column strips, plot background).
 * Uses cached skeleton — no recomputation.
 * Per-cell elements (ticks, axis lines, row strips) are in viewport chrome.
 *
 * @param {GGRSRenderer} renderer
 * @returns {Object} Parsed LayoutInfo subset (static elements only)
 */
function ggrsGetStaticChrome(renderer) {
    const json = renderer.getStaticChrome();
    const result = JSON.parse(json);
    if (result.error) {
        throw new Error('[GGRS] getStaticChrome failed: ' + result.error);
    }
    return result;
}

/**
 * Get viewport chrome layout (panels, grid, row strips, ticks, axis lines, borders).
 * Uses cached skeleton + viewport range.
 *
 * @param {GGRSRenderer} renderer
 * @param {string} viewportJson - Viewport filter JSON (kept for API compat)
 * @returns {Object} Parsed LayoutInfo subset (all per-cell elements)
 */
function ggrsGetViewportChrome(renderer, viewportJson) {
    const json = renderer.getViewportChrome(viewportJson);
    const result = JSON.parse(json);
    if (result.error) {
        throw new Error('[GGRS] getViewportChrome failed: ' + result.error);
    }
    return result;
}

/**
 * Render static chrome: GPU buffer + static text canvas.
 * Creates the split-buffer DOM structure on first call.
 * Written once per skeleton change (resize, zoom, binding change).
 *
 * @param {string} containerId
 * @param {Object} layoutInfo - Static chrome from ggrsGetStaticChrome
 * @returns {Promise<void>}
 */
async function ggrsRenderStaticChrome(containerId, layoutInfo) {
    const w = layoutInfo.width;
    const h = layoutInfo.height;
    const { gpu, container } = await _ensureSplitDom(containerId, w, h);

    // GPU: build static chrome buffer (no scroll offset)
    gpu.setStaticChrome(layoutInfo);

    // Text: draw static text on static canvas
    const staticTexts = _collectTexts(layoutInfo);
    const dpr = window.devicePixelRatio || 1;
    const staticTextCanvas = container.querySelector('.ggrs-text-static');
    if (staticTextCanvas) {
        _drawTextsOnCanvas(staticTextCanvas, staticTexts, dpr);
    }
}

/**
 * Render viewport chrome: GPU buffer + viewport text canvas.
 * Rebuilt on scroll/viewport change. GPU must already be initialized.
 *
 * @param {string} containerId
 * @param {Object} layoutInfo - Viewport chrome from ggrsGetViewportChrome
 */
function ggrsRenderViewportChrome(containerId, layoutInfo) {
    const container = document.getElementById(containerId);
    if (!container) throw new Error('[GGRS] Container not found: ' + containerId);

    const gpu = container._ggrsGpu;
    if (!gpu) throw new Error('[GGRS] GPU not initialized. Call ggrsRenderStaticChrome first.');

    // GPU: build viewport chrome buffer (with scroll offset)
    gpu.setViewportChrome(layoutInfo);

    // Clear old data points (invalid for new viewport positions)
    gpu.clearViewportPoints();

    // Text: draw viewport text on viewport canvas
    const vpTexts = _collectTexts(layoutInfo);
    const dpr = window.devicePixelRatio || 1;
    const vpTextCanvas = container.querySelector('.ggrs-text-viewport');
    if (vpTextCanvas) {
        _drawTextsOnCanvas(vpTextCanvas, vpTexts, dpr);
        vpTextCanvas.style.transform = '';  // Reset any scroll transform
    }

    // Reset view transform (new viewport = new positions)
    gpu.resetViewTransform();
}

/**
 * Clear viewport chrome + data points on GPU and viewport text canvas.
 * Called before viewport re-render on scroll.
 *
 * @param {string} containerId
 */
function ggrsClearViewport(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const gpu = container._ggrsGpu;
    if (gpu) {
        gpu.clearViewport();
        gpu.requestRedraw();
    }

    const vpTextCanvas = container.querySelector('.ggrs-text-viewport');
    if (vpTextCanvas) {
        const ctx = vpTextCanvas.getContext('2d');
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, vpTextCanvas.width, vpTextCanvas.height);
        vpTextCanvas.style.transform = '';
    }
}

/**
 * Clear all split buffers (static + viewport) and text canvases.
 * Called on binding change / full re-render.
 *
 * @param {string} containerId
 */
function ggrsClearAll(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const gpu = container._ggrsGpu;
    if (gpu) {
        gpu.clearAll();
        gpu.requestRedraw();
    }

    for (const cls of ['.ggrs-text-static', '.ggrs-text-viewport']) {
        const canvas = container.querySelector(cls);
        if (canvas) {
            const ctx = canvas.getContext('2d');
            ctx.setTransform(1, 0, 0, 1, 0, 0);
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            canvas.style.transform = '';
        }
    }
}

// Expose to window for Dart interop
window.ggrsAttachViewportHandlers = ggrsAttachViewportHandlers;
window.ensureWasmInitialized = ensureWasmInitialized;
window.createGGRSRenderer = createGGRSRenderer;
window.ggrsCreateTextMeasurer = ggrsCreateTextMeasurer;
window.ggrsComputeLayout = ggrsComputeLayout;
window.ggrsRenderChrome = ggrsRenderChrome;
window.ggrsCreateChromeLayers = ggrsCreateChromeLayers;
window.ggrsRenderChromeBatch = ggrsRenderChromeBatch;
window.ggrsRenderDataPoints = ggrsRenderDataPoints;
window.ggrsClearDataCanvas = ggrsClearDataCanvas;
window.ggrsRenderChromeCanvas = ggrsRenderChromeCanvas;
window.ggrsInitPlotStream = ggrsInitPlotStream;
window.ggrsGetStreamLayout = ggrsGetStreamLayout;
window.ggrsLoadAndMapChunk = ggrsLoadAndMapChunk;
window.ggrsSetViewTransform = ggrsSetViewTransform;
window.ggrsResetViewTransform = ggrsResetViewTransform;
window.ggrsBeginStaging = ggrsBeginStaging;
window.ggrsCommitRender = ggrsCommitRender;
// Split-buffer API (Phase 1.2+)
window.ggrsComputeSkeleton = ggrsComputeSkeleton;
window.ggrsGetStaticChrome = ggrsGetStaticChrome;
window.ggrsGetViewportChrome = ggrsGetViewportChrome;
window.ggrsRenderStaticChrome = ggrsRenderStaticChrome;
window.ggrsRenderViewportChrome = ggrsRenderViewportChrome;
window.ggrsClearViewport = ggrsClearViewport;
window.ggrsClearAll = ggrsClearAll;

// Auto-initialize WASM when module loads
console.log('[GGRS] Bootstrap loaded, starting auto-initialization...');
ensureWasmInitialized();
*/
