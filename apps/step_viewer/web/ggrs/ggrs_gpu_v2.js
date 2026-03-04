/* DEPRECATED: This file has been replaced by ggrs_gpu_v2_v3.js
 * All code below is commented out and should not be used.
 * Date: 2026-03-03
 */

/*
/**
 * WebGPU renderer for GGRS v2 — data-space GPU rendering.
 *
 * Key difference from v1: data points are stored in data-space coordinates.
 * The vertex shader projects data→pixels using view uniforms (axis ranges).
 * Zoom/pan = write 16 bytes to a uniform buffer. No WASM round-trip.
 *
 * Two pipelines:
 *   1. Rect  — pixel-space chrome (backgrounds, lines, borders, strip fills)
 *   2. Point — data-space points (SDF circle, projected to pixels by vertex shader)
 */

// ─── WGSL Shaders ─────────────────────────────────────────────────────────────

/** Chrome rect shader — surface-space, scroll_offset subtracted for screen position. */
const RECT_SHADER_V2 = /* wgsl */`
struct RectUniforms {
    canvas_size: vec2f,     // offset 0, 8 bytes
    scroll_offset: vec2f,   // offset 8, 8 bytes — total surface scroll
}
@group(0) @binding(0) var<uniform> u: RectUniforms;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
}

@vertex
fn vs_main(
    @builtin(vertex_index) vi: u32,
    @location(0) rect_pos: vec2f,
    @location(1) rect_size: vec2f,
    @location(2) color: vec4f,
) -> VertexOutput {
    let corner = vec2f(f32(vi & 1u), f32((vi >> 1u) & 1u));
    let pos = rect_pos + corner * rect_size - u.scroll_offset;
    let ndc = vec2f(
        pos.x / u.canvas_size.x * 2.0 - 1.0,
        1.0 - pos.y / u.canvas_size.y * 2.0,
    );
    var out: VertexOutput;
    out.position = vec4f(ndc, 0.0, 1.0);
    out.color = color;
    return out;
}

@fragment
fn fs_main(@location(0) color: vec4f) -> @location(0) vec4f {
    return color;
}
`;

/** Data-space point shader — projects data coords to pixels using view uniforms. */
const POINT_SHADER_V2 = /* wgsl */`
struct ViewUniforms {
    canvas_size: vec2f,
    x_range: vec2f,         // (x_min, x_max) — THE ZOOM
    y_range: vec2f,         // (y_min, y_max) — THE ZOOM
    grid_origin: vec2f,     // (margin_left, margin_top)
    cell_size: vec2f,       // (cell_width, cell_height)
    cell_spacing: f32,
    n_visible_cols: u32,
    n_visible_rows: u32,
    viewport_col_start: u32,
    viewport_row_start: u32,
    _pad0: f32,
    scroll_offset: vec2f,   // smooth pixel offset for facet scrolling
    _pad1: vec2f,
    data_insets: vec4f,     // (left, top, right, bottom) — axis margins within cell
}
@group(0) @binding(0) var<uniform> v: ViewUniforms;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
    @location(1) color: vec4f,
}

@vertex
fn vs_main(
    @builtin(vertex_index) vi: u32,
    @location(0) data_xy: vec2f,
    @location(1) facet_cr: vec2u,
    @location(2) color_packed: u32,
    @location(3) size: f32,
) -> VertexOutput {
    // Compute visible panel index
    let pc = i32(facet_cr.x) - i32(v.viewport_col_start);
    let pr = i32(facet_cr.y) - i32(v.viewport_row_start);

    // Clip if outside visible panels
    if (pc < 0 || pc >= i32(v.n_visible_cols) || pr < 0 || pr >= i32(v.n_visible_rows)) {
        var out: VertexOutput;
        out.position = vec4f(0.0, 0.0, 0.0, 0.0);  // degenerate
        out.uv = vec2f(0.0);
        out.color = vec4f(0.0);
        return out;
    }

    // Normalize data to [0,1] within current axis range
    let x_span = v.x_range.y - v.x_range.x;
    let y_span = v.y_range.y - v.y_range.x;
    let nx = select((data_xy.x - v.x_range.x) / x_span, 0.5, abs(x_span) < 1e-15);
    let ny = select((data_xy.y - v.y_range.x) / y_span, 0.5, abs(y_span) < 1e-15);

    // Clip to visible data range (fixed pixel margin for point radius)
    let margin_x = size / v.cell_size.x;
    let margin_y = size / v.cell_size.y;
    if (nx < -margin_x || nx > 1.0 + margin_x || ny < -margin_y || ny > 1.0 + margin_y) {
        var clip_out: VertexOutput;
        clip_out.position = vec4f(2.0, 2.0, 0.0, 1.0);  // off-screen (NDC > 1.0)
        clip_out.uv = vec2f(0.0);
        clip_out.color = vec4f(0.0);
        return clip_out;
    }

    // Panel origin in pixel space (with smooth scroll offset)
    let step_x = v.cell_size.x + v.cell_spacing;
    let step_y = v.cell_size.y + v.cell_spacing;
    let panel_x = v.grid_origin.x + f32(pc) * step_x + v.scroll_offset.x;
    let panel_y = v.grid_origin.y + f32(pr) * step_y + v.scroll_offset.y;

    // Data area dimensions (cell minus axis margins)
    let data_area_width = v.cell_size.x - v.data_insets.x - v.data_insets.z;
    let data_area_height = v.cell_size.y - v.data_insets.y - v.data_insets.w;

    // Screen position within data area: x left→right, y top→bottom (Y inverted)
    let cx = panel_x + v.data_insets.x + nx * data_area_width;
    let cy = panel_y + v.data_insets.y + (1.0 - ny) * data_area_height;

    // Quad expansion for SDF circle
    let corner = vec2f(f32(vi & 1u), f32((vi >> 1u) & 1u));
    let uv = corner * 2.0 - 1.0;
    let pos = vec2f(cx, cy) + uv * size;

    // NDC conversion
    let ndc = vec2f(
        pos.x / v.canvas_size.x * 2.0 - 1.0,
        1.0 - pos.y / v.canvas_size.y * 2.0,
    );

    // Unpack RGBA from u32 (big-endian: R<<24 | G<<16 | B<<8 | A)
    let r = f32((color_packed >> 24u) & 0xFFu) / 255.0;
    let g = f32((color_packed >> 16u) & 0xFFu) / 255.0;
    let b = f32((color_packed >> 8u) & 0xFFu) / 255.0;
    let a = f32(color_packed & 0xFFu) / 255.0;

    var out: VertexOutput;
    out.position = vec4f(ndc, 0.0, 1.0);
    out.uv = uv;
    out.color = vec4f(r, g, b, a);
    return out;
}

@fragment
fn fs_main(@location(0) uv: vec2f, @location(1) color: vec4f) -> @location(0) vec4f {
    let d = length(uv) - 1.0;
    let aa = fwidth(d);
    let alpha = 1.0 - smoothstep(-aa, aa, d);
    if (alpha < 0.01) { discard; }
    return vec4f(color.rgb, color.a * alpha);
}
`;

// ─── Color Helpers ─────────────────────────────────────────────────────────────

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
        return [
            parseInt(parts[0]) / 255,
            parseInt(parts[1]) / 255,
            parseInt(parts[2]) / 255,
            parseFloat(parts[3]),
        ];
    }
    if (str && str.startsWith('rgb(')) {
        const parts = str.slice(4, -1).split(',').map(s => s.trim());
        return [parseInt(parts[0]) / 255, parseInt(parts[1]) / 255, parseInt(parts[2]) / 255, 1.0];
    }
    throw new Error('[GGRS-V2] _parseColor: unrecognized color: ' + JSON.stringify(str));
}

function _packColorU32(r, g, b, a) {
    return (((Math.round(r * 255) & 0xFF) << 24) |
            ((Math.round(g * 255) & 0xFF) << 16) |
            ((Math.round(b * 255) & 0xFF) << 8) |
            (Math.round(a * 255) & 0xFF)) >>> 0;
}

// ─── Constants ─────────────────────────────────────────────────────────────────

const RECT_BYTES_PER_INSTANCE = 32;  // 8 × f32: pos(2) + size(2) + color(4)
const POINT_BYTES_PER_INSTANCE = 24; // data_xy(2×f32) + facet_cr(2×u32) + color_packed(u32) + size(f32)
const INITIAL_POINT_CAPACITY = 100000;
const BUFFER_USAGE = GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC;

// View uniform size: 80 bytes (64 + scroll_offset vec2f + _pad1 vec2f)
const VIEW_UNIFORM_SIZE = 96;  // 80 + 16 (vec4f data_insets)
// Rect uniform size: 8 bytes (padded to 16 for alignment)
const RECT_UNIFORM_SIZE = 16;

// ─── GgrsGpuV2 ────────────────────────────────────────────────────────────────

export class GgrsGpuV2 {
    constructor() {
        this._device = null;
        this._context = null;
        this._format = null;
        this._canvas = null;

        // Pipelines
        this._rectPipeline = null;
        this._pointPipeline = null;

        // Uniform buffers
        this._rectUniformBuffer = null;
        this._rectBindGroup = null;
        this._viewUniformBuffer = null;
        this._viewBindGroup = null;

        // Geometry buffers
        this._layers = new Map();    // name → { buffer, count } — ordered by insertion
        this._pointBuffer = null;    // { buffer, count, capacity }

        // Canvas logical dimensions
        this._width = 0;
        this._height = 0;

        // View state (for interaction handler to read)
        this.xMin = 0;
        this.xMax = 1;
        this.yMin = 0;
        this.yMax = 1;

        // Panel layout (for interaction handler)
        this.gridOriginX = 0;
        this.gridOriginY = 0;
        this.cellWidth = 0;
        this.cellHeight = 0;
        this.cellSpacing = 0;
        this.nVisibleCols = 1;
        this.nVisibleRows = 1;

        // Clear color
        this._clearColor = { r: 1, g: 1, b: 1, a: 1 };

        // Deferred render
        this._dirty = false;
        this._rafId = null;
    }

    // ── Init ───────────────────────────────────────────────────────────────────

    async init(canvas) {
        if (!navigator.gpu) {
            throw new Error('[GGRS-V2] WebGPU is not available in this browser');
        }
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) {
            throw new Error('[GGRS-V2] WebGPU adapter not available');
        }
        this._device = await adapter.requestDevice();
        this._device.lost.then(info => {
            console.error('[GGRS-V2] DEVICE LOST:', info.reason, info.message);
        });
        this._canvas = canvas;
        this._format = navigator.gpu.getPreferredCanvasFormat();

        this._context = canvas.getContext('webgpu');
        this._context.configure({
            device: this._device,
            format: this._format,
            alphaMode: 'opaque',
        });

        this._createUniforms();
        this._createPipelines();
    }

    _createUniforms() {
        const device = this._device;

        // Rect uniform: 8 bytes vec2f canvas_size (padded to 16 for alignment)
        this._rectUniformBuffer = device.createBuffer({
            size: RECT_UNIFORM_SIZE,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });

        // View uniform: 64 bytes
        this._viewUniformBuffer = device.createBuffer({
            size: VIEW_UNIFORM_SIZE,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });

        const rectBGL = device.createBindGroupLayout({
            entries: [{
                binding: 0,
                visibility: GPUShaderStage.VERTEX,
                buffer: { type: 'uniform' },
            }],
        });
        this._rectBindGroup = device.createBindGroup({
            layout: rectBGL,
            entries: [{ binding: 0, resource: { buffer: this._rectUniformBuffer } }],
        });

        const viewBGL = device.createBindGroupLayout({
            entries: [{
                binding: 0,
                visibility: GPUShaderStage.VERTEX,
                buffer: { type: 'uniform' },
            }],
        });
        this._viewBindGroup = device.createBindGroup({
            layout: viewBGL,
            entries: [{ binding: 0, resource: { buffer: this._viewUniformBuffer } }],
        });

        // Store layouts for pipeline creation
        this._rectBGL = rectBGL;
        this._viewBGL = viewBGL;
    }

    _createPipelines() {
        const device = this._device;

        // Rect pipeline (pixel-space chrome)
        const rectModule = device.createShaderModule({ code: RECT_SHADER_V2 });
        this._rectPipeline = device.createRenderPipeline({
            layout: device.createPipelineLayout({ bindGroupLayouts: [this._rectBGL] }),
            vertex: {
                module: rectModule,
                entryPoint: 'vs_main',
                buffers: [{
                    arrayStride: RECT_BYTES_PER_INSTANCE,
                    stepMode: 'instance',
                    attributes: [
                        { shaderLocation: 0, offset: 0, format: 'float32x2' },   // rect_pos
                        { shaderLocation: 1, offset: 8, format: 'float32x2' },   // rect_size
                        { shaderLocation: 2, offset: 16, format: 'float32x4' },  // color
                    ],
                }],
            },
            fragment: {
                module: rectModule,
                entryPoint: 'fs_main',
                targets: [{
                    format: this._format,
                    blend: {
                        color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' },
                        alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' },
                    },
                }],
            },
            primitive: { topology: 'triangle-strip', stripIndexFormat: 'uint32' },
        });

        // Point pipeline (data-space points)
        const pointModule = device.createShaderModule({ code: POINT_SHADER_V2 });
        this._pointPipeline = device.createRenderPipeline({
            layout: device.createPipelineLayout({ bindGroupLayouts: [this._viewBGL] }),
            vertex: {
                module: pointModule,
                entryPoint: 'vs_main',
                buffers: [{
                    arrayStride: POINT_BYTES_PER_INSTANCE,
                    stepMode: 'instance',
                    attributes: [
                        { shaderLocation: 0, offset: 0, format: 'float32x2' },   // data_xy
                        { shaderLocation: 1, offset: 8, format: 'uint32x2' },    // facet_cr
                        { shaderLocation: 2, offset: 16, format: 'uint32' },     // color_packed
                        { shaderLocation: 3, offset: 20, format: 'float32' },    // size
                    ],
                }],
            },
            fragment: {
                module: pointModule,
                entryPoint: 'fs_main',
                targets: [{
                    format: this._format,
                    blend: {
                        color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' },
                        alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' },
                    },
                }],
            },
            primitive: { topology: 'triangle-strip', stripIndexFormat: 'uint32' },
        });
    }

    // ── Canvas size ────────────────────────────────────────────────────────────

    setCanvasSize(w, h) {
        this._width = w;
        this._height = h;
        const dpr = window.devicePixelRatio || 1;
        this._canvas.width = Math.round(w * dpr);
        this._canvas.height = Math.round(h * dpr);
        this._canvas.style.width = w + 'px';
        this._canvas.style.height = h + 'px';

        // Update rect uniform
        this._device.queue.writeBuffer(
            this._rectUniformBuffer, 0, new Float32Array([w, h])
        );
        // Update view uniform canvas_size (first 8 bytes)
        this._device.queue.writeBuffer(
            this._viewUniformBuffer, 0, new Float32Array([w, h])
        );
    }

    // ── View uniforms (full 80-byte write) ─────────────────────────────────────

    setViewUniforms(params) {
        this.xMin = params.xMin;
        this.xMax = params.xMax;
        this.yMin = params.yMin;
        this.yMax = params.yMax;
        this.gridOriginX = params.gridOriginX;
        this.gridOriginY = params.gridOriginY;
        this.cellWidth = params.cellWidth;
        this.cellHeight = params.cellHeight;
        this.cellSpacing = params.cellSpacing;
        this.nVisibleCols = params.nVisibleCols;
        this.nVisibleRows = params.nVisibleRows;

        const buf = new ArrayBuffer(VIEW_UNIFORM_SIZE);
        const f32 = new Float32Array(buf);
        const u32 = new Uint32Array(buf);

        f32[0] = this._width;           // canvas_size.x
        f32[1] = this._height;          // canvas_size.y
        f32[2] = params.xMin;           // x_range.x
        f32[3] = params.xMax;           // x_range.y
        f32[4] = params.yMin;           // y_range.x
        f32[5] = params.yMax;           // y_range.y
        f32[6] = params.gridOriginX;    // grid_origin.x
        f32[7] = params.gridOriginY;    // grid_origin.y
        f32[8] = params.cellWidth;      // cell_size.x
        f32[9] = params.cellHeight;     // cell_size.y
        f32[10] = params.cellSpacing;   // cell_spacing
        u32[11] = params.nVisibleCols;  // n_visible_cols
        u32[12] = params.nVisibleRows;  // n_visible_rows
        u32[13] = params.vpColStart || 0;  // viewport_col_start
        u32[14] = params.vpRowStart || 0;  // viewport_row_start
        f32[15] = 0;                    // _pad0
        f32[16] = 0;                    // scroll_offset.x
        f32[17] = 0;                    // scroll_offset.y
        f32[18] = 0;                    // _pad1.x
        f32[19] = 0;                    // _pad1.y
        f32[20] = params.dataInsetLeft || 0;    // data_insets.x (left)
        f32[21] = params.dataInsetTop || 0;     // data_insets.y (top)
        f32[22] = params.dataInsetRight || 0;   // data_insets.z (right)
        f32[23] = params.dataInsetBottom || 0;  // data_insets.w (bottom)

        this._device.queue.writeBuffer(this._viewUniformBuffer, 0, buf);
        this.requestRedraw();
    }

    /**
     * Sync full layout state from PlotState (convenience wrapper for setViewUniforms).
     * @param {string} layoutStateJson - JSON string from PlotState.buildLayoutState()
     */
    syncLayoutState(layoutStateJson) {
        const state = JSON.parse(layoutStateJson);
        this.setViewUniforms({
            xMin: state.vis_x_min,
            xMax: state.vis_x_max,
            yMin: state.vis_y_min,
            yMax: state.vis_y_max,
            gridOriginX: state.grid_origin_x,
            gridOriginY: state.grid_origin_y,
            cellWidth: state.cell_width,
            cellHeight: state.cell_height,
            cellSpacing: state.cell_spacing,
            nVisibleCols: state.n_visible_cols,
            nVisibleRows: state.n_visible_rows,
            vpColStart: state.viewport_col_start,
            vpRowStart: state.viewport_row_start,
            dataInsetLeft: state.data_inset_left,
            dataInsetTop: state.data_inset_top,
            dataInsetRight: state.data_inset_right,
            dataInsetBottom: state.data_inset_bottom,
        });
    }

    // ── Axis range (16-byte write — THE ZOOM) ──────────────────────────────────

    setAxisRange(xMin, xMax, yMin, yMax) {
        this.xMin = xMin;
        this.xMax = xMax;
        this.yMin = yMin;
        this.yMax = yMax;
        this._device.queue.writeBuffer(
            this._viewUniformBuffer, 8,  // offset 8 = x_range
            new Float32Array([xMin, xMax, yMin, yMax])
        );
        this.requestRedraw();
    }

    // ── Cell size (8-byte write — facet zoom) ────────────────────────────────

    setCellSize(w, h) {
        this.cellWidth = w;
        this.cellHeight = h;
        this._device.queue.writeBuffer(
            this._viewUniformBuffer, 32,  // offset 32 = cell_size
            new Float32Array([w, h])
        );
        this.requestRedraw();
    }

    // ── Visible counts (8-byte write — multi-facet zoom) ─────────────────────

    setVisibleCounts(cols, rows) {
        this.nVisibleCols = cols;
        this.nVisibleRows = rows;
        this._device.queue.writeBuffer(
            this._viewUniformBuffer, 44,  // offset 44 = n_visible_cols (u32), n_visible_rows (u32)
            new Uint32Array([cols, rows])
        );
        this.requestRedraw();
    }

    // ── Scroll offset (8-byte write — smooth facet scrolling) ───────────────

    setScrollOffset(dx, dy) {
        this._device.queue.writeBuffer(
            this._viewUniformBuffer, 64,  // offset 64 = scroll_offset
            new Float32Array([dx, dy])
        );
        this.requestRedraw();
    }

    // ── Facet viewport (8-byte write — discrete facet indices) ────────────

    setFacetViewport(colStart, rowStart) {
        this._device.queue.writeBuffer(
            this._viewUniformBuffer, 52,  // offset 52 = viewport_col_start
            new Uint32Array([colStart, rowStart])
        );
        this.requestRedraw();
    }

    // ── Rect scroll (8-byte write — V3 surface scroll for chrome) ─────────────

    setRectScroll(x, y) {
        this._device.queue.writeBuffer(
            this._rectUniformBuffer, 8,  // offset 8 = scroll_offset
            new Float32Array([x, y])
        );
        this.requestRedraw();
    }

    // ── Named rect layers ─────────────────────────────────────────────────────

    /**
     * Create or replace a named rect layer. Other layers are untouched.
     * Registration order (first setLayer call) = z-order.
     * @param {string} name - Layer name (e.g. 'panel_backgrounds', 'grid_lines')
     * @param {Array} rects - Array of { x, y, width, height, color: [r,g,b,a] }
     */
    setLayer(name, rects) {
        const old = this._layers.get(name);

        // Destroy old GPU buffer
        if (old) old.buffer.destroy();

        if (!rects || rects.length === 0) {
            // Remove empty layers from the map
            if (old) this._layers.delete(name);
            this.requestRedraw();
            return;
        }

        const count = rects.length;
        const data = new Float32Array(count * 8);  // 8 floats per rect
        for (let i = 0; i < count; i++) {
            const r = rects[i];
            const offset = i * 8;
            data[offset + 0] = r.x;
            data[offset + 1] = r.y;
            data[offset + 2] = r.width;
            data[offset + 3] = r.height;
            data[offset + 4] = r.color[0];
            data[offset + 5] = r.color[1];
            data[offset + 6] = r.color[2];
            data[offset + 7] = r.color[3];
        }

        const buffer = this._device.createBuffer({
            size: data.byteLength,
            usage: BUFFER_USAGE,
        });
        this._device.queue.writeBuffer(buffer, 0, data);

        if (old) {
            // Update in place — preserves Map insertion order (= z-order)
            old.buffer = buffer;
            old.count = count;
        } else {
            this._layers.set(name, { buffer, count });
        }
        this.requestRedraw();
    }

    /**
     * Remove and destroy a single named layer.
     */
    removeLayer(name) {
        const layer = this._layers.get(name);
        if (layer) {
            layer.buffer.destroy();
            this._layers.delete(name);
            this.requestRedraw();
        }
    }

    /**
     * Destroy all named layers.
     */
    clearAllLayers() {
        for (const layer of this._layers.values()) {
            layer.buffer.destroy();
        }
        this._layers.clear();
    }

    // ── Data points (append to growable buffer) ────────────────────────────────

    appendDataPoints(points, options) {
        if (!points || points.length === 0) return;

        const fillColor = options?.fillColor || 'rgba(0,0,0,0.6)';
        const radius = options?.radius || 2.5;
        const [r, g, b, a] = _parseColor(fillColor);
        const colorPacked = _packColorU32(r, g, b, a);

        const newCount = points.length;

        // Ensure buffer capacity
        if (!this._pointBuffer) {
            const capacity = Math.max(INITIAL_POINT_CAPACITY, newCount);
            const buffer = this._device.createBuffer({
                size: capacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            this._pointBuffer = { buffer, count: 0, capacity };
        }

        const current = this._pointBuffer;
        if (current.count + newCount > current.capacity) {
            const newCapacity = Math.max(current.capacity * 2, current.count + newCount);
            const newBuffer = this._device.createBuffer({
                size: newCapacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            // Copy existing data
            const encoder = this._device.createCommandEncoder();
            encoder.copyBufferToBuffer(
                current.buffer, 0, newBuffer, 0,
                current.count * POINT_BYTES_PER_INSTANCE
            );
            this._device.queue.submit([encoder.finish()]);
            current.buffer.destroy();
            current.buffer = newBuffer;
            current.capacity = newCapacity;
        }

        // Write new points
        const data = new ArrayBuffer(newCount * POINT_BYTES_PER_INSTANCE);
        const f32View = new Float32Array(data);
        const u32View = new Uint32Array(data);

        for (let i = 0; i < newCount; i++) {
            const p = points[i];
            const base = i * 6;  // 24 bytes / 4 = 6 uint32s per point
            f32View[base + 0] = p.x;
            f32View[base + 1] = p.y;
            u32View[base + 2] = p.ci;
            u32View[base + 3] = p.ri;
            u32View[base + 4] = colorPacked;
            f32View[base + 5] = radius;
        }

        this._device.queue.writeBuffer(
            current.buffer,
            current.count * POINT_BYTES_PER_INSTANCE,
            data
        );
        current.count += newCount;
        this.requestRedraw();
    }

    /**
     * Append data points from a packed binary buffer (16 bytes/point from WASM).
     * Input format: [x:f32, y:f32, ci:u32, ri:u32] per point (little-endian).
     * Expands to 24 bytes/point by appending colorPacked and radius.
     * @param {Uint8Array} packedBuffer - Binary buffer from WASM loadDataChunkPacked
     * @param {Object} options - { fillColor?: string, radius?: number }
     */
    appendDataPointsFromBuffer(packedBuffer, options) {
        if (!packedBuffer || packedBuffer.byteLength === 0) return;

        const PACKED_BYTES = 16;  // x:f32, y:f32, ci:u32, ri:u32
        const newCount = packedBuffer.byteLength / PACKED_BYTES;
        if (newCount === 0) return;

        const fillColor = options?.fillColor || 'rgba(0,0,0,0.6)';
        const radius = options?.radius || 2.5;
        const [r, g, b, a] = _parseColor(fillColor);
        const colorPacked = _packColorU32(r, g, b, a);

        // Ensure buffer capacity (same logic as appendDataPoints)
        if (!this._pointBuffer) {
            const capacity = Math.max(INITIAL_POINT_CAPACITY, newCount);
            const buffer = this._device.createBuffer({
                size: capacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            this._pointBuffer = { buffer, count: 0, capacity };
        }

        const current = this._pointBuffer;
        if (current.count + newCount > current.capacity) {
            const newCapacity = Math.max(current.capacity * 2, current.count + newCount);
            const newBuffer = this._device.createBuffer({
                size: newCapacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            const encoder = this._device.createCommandEncoder();
            encoder.copyBufferToBuffer(
                current.buffer, 0, newBuffer, 0,
                current.count * POINT_BYTES_PER_INSTANCE
            );
            this._device.queue.submit([encoder.finish()]);
            current.buffer.destroy();
            current.buffer = newBuffer;
            current.capacity = newCapacity;
        }

        // Read packed input as typed views
        const srcF32 = new Float32Array(packedBuffer.buffer, packedBuffer.byteOffset, newCount * 4);
        const srcU32 = new Uint32Array(packedBuffer.buffer, packedBuffer.byteOffset, newCount * 4);

        // Build expanded 24-byte-per-point buffer
        const data = new ArrayBuffer(newCount * POINT_BYTES_PER_INSTANCE);
        const dstF32 = new Float32Array(data);
        const dstU32 = new Uint32Array(data);

        for (let i = 0; i < newCount; i++) {
            const srcBase = i * 4;   // 16 bytes / 4 = 4 u32s per input point
            const dstBase = i * 6;   // 24 bytes / 4 = 6 u32s per output point
            dstF32[dstBase + 0] = srcF32[srcBase + 0];  // x
            dstF32[dstBase + 1] = srcF32[srcBase + 1];  // y
            dstU32[dstBase + 2] = srcU32[srcBase + 2];  // ci
            dstU32[dstBase + 3] = srcU32[srcBase + 3];  // ri
            dstU32[dstBase + 4] = colorPacked;
            dstF32[dstBase + 5] = radius;
        }

        this._device.queue.writeBuffer(
            current.buffer,
            current.count * POINT_BYTES_PER_INSTANCE,
            data
        );
        current.count += newCount;
        this.requestRedraw();
    }

    clearDataPoints() {
        if (this._pointBuffer) {
            this._pointBuffer.buffer.destroy();
            this._pointBuffer = null;
        }
        this.requestRedraw();
    }

    clearAll() {
        this.clearAllLayers();
        this.clearDataPoints();
        this.requestRedraw();
    }

    // ── Deferred render ────────────────────────────────────────────────────────

    requestRedraw() {
        if (this._dirty) return;
        this._dirty = true;
        this._rafId = requestAnimationFrame(() => {
            this._dirty = false;
            this._rafId = null;
            this._render();
        });
    }

    _render() {
        if (!this._device || !this._context) return;

        const encoder = this._device.createCommandEncoder();
        const pass = encoder.beginRenderPass({
            colorAttachments: [{
                view: this._context.getCurrentTexture().createView(),
                clearValue: this._clearColor,
                loadOp: 'clear',
                storeOp: 'store',
            }],
        });

        // Named rect layers (pixel-space) — drawn in insertion order
        if (this._layers.size > 0) {
            pass.setPipeline(this._rectPipeline);
            pass.setBindGroup(0, this._rectBindGroup);
            for (const layer of this._layers.values()) {
                if (layer.count > 0) {
                    pass.setVertexBuffer(0, layer.buffer);
                    pass.draw(4, layer.count, 0, 0);
                }
            }
        }

        // Data points (data-space, projected by vertex shader) — always last
        if (this._pointBuffer && this._pointBuffer.count > 0) {
            pass.setPipeline(this._pointPipeline);
            pass.setBindGroup(0, this._viewBindGroup);
            pass.setVertexBuffer(0, this._pointBuffer.buffer);
            pass.draw(4, this._pointBuffer.count, 0, 0);
        }

        pass.end();
        this._device.queue.submit([encoder.finish()]);
    }

}
*/
