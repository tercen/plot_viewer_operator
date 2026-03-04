/* DEPRECATED: This file has been replaced by ggrs_gpu_v3.js
 * All code below is commented out and should not be used.
 * Date: 2026-03-03
 */

/*
/**
 * WebGPU renderer for GGRS plot visualization.
 *
 * Replaces Canvas 2D background/chrome/data layers with a single WebGPU canvas.
 * Enables smooth facet scrolling via GPU uniform offset (sub-ms).
 *
 * Two pipelines:
 *   1. Rect — backgrounds, lines (as thin rects), borders, strip fills
 *   2. Point — data points (SDF circle, extensible to 26 ggplot2 shapes)
 *
 * Two rendering paths:
 *   Legacy — single BufferSet (setChromeGeometry + appendDataPoints), single uniform
 *   Split  — staticChrome + viewportChrome + viewportPoints, two uniforms
 *
 * Split path uses two uniform buffers:
 *   _uniformBuffer       — canvas_size + view_translate + view_scale (viewport elements)
 *   _staticUniformBuffer — canvas_size + identity transform       (static elements, no zoom/pan)
 *
 * Render order (split path):
 *   1. Viewport chrome (panels, grid, row strips, borders) — with scroll offset
 *   2. Static chrome (axes, ticks, column strips) — no scroll offset, ON TOP of panels
 *   3. Viewport data points — with scroll offset, topmost
 */

// ─── WGSL Shaders ─────────────────────────────────────────────────────────────

const RECT_SHADER = /* wgsl */`
struct Uniforms {
    canvas_size: vec2f,
    view_translate: vec2f,
    view_scale: vec2f,
}
@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec4f,
}

// Instance attributes: rect_pos(x,y), rect_size(w,h), color(r,g,b,a)
@vertex
fn vs_main(
    @builtin(vertex_index) vi: u32,
    @location(0) rect_pos: vec2f,
    @location(1) rect_size: vec2f,
    @location(2) color: vec4f,
) -> VertexOutput {
    // Triangle-strip: 0=TL, 1=TR, 2=BL, 3=BR
    let corner = vec2f(f32(vi & 1u), f32((vi >> 1u) & 1u));
    let pos = rect_pos + corner * rect_size;
    let transformed = pos * u.view_scale + u.view_translate;

    // Logical pixels → NDC: x [0,W]→[-1,1], y [0,H]→[+1,-1]
    let ndc = vec2f(
        transformed.x / u.canvas_size.x * 2.0 - 1.0,
        1.0 - transformed.y / u.canvas_size.y * 2.0,
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

const POINT_SHADER = /* wgsl */`
struct Uniforms {
    canvas_size: vec2f,
    view_translate: vec2f,
    view_scale: vec2f,
}
@group(0) @binding(0) var<uniform> u: Uniforms;

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) uv: vec2f,
    @location(1) color: vec4f,
}

@vertex
fn vs_main(
    @builtin(vertex_index) vi: u32,
    @location(0) center: vec2f,
    @location(1) size: f32,
    @location(2) color_packed: u32,
    @location(3) shape_idx: u32,
) -> VertexOutput {
    // Triangle-strip quad: 0=TL, 1=TR, 2=BL, 3=BR
    let corner = vec2f(f32(vi & 1u), f32((vi >> 1u) & 1u));
    let uv = corner * 2.0 - 1.0;  // [-1, 1]

    let pos = center + uv * size;
    let transformed = pos * u.view_scale + u.view_translate;
    let ndc = vec2f(
        transformed.x / u.canvas_size.x * 2.0 - 1.0,
        1.0 - transformed.y / u.canvas_size.y * 2.0,
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
    // Circle SDF: negative inside, zero on edge, positive outside
    let d = length(uv) - 1.0;
    let aa = fwidth(d);
    let alpha = 1.0 - smoothstep(-aa, aa, d);
    if (alpha < 0.01) { discard; }
    return vec4f(color.rgb, color.a * alpha);
}
`;

// ─── Color Helpers ─────────────────────────────────────────────────────────────

/** Parse CSS color string → [r, g, b, a] as 0–1 floats.
 *  Colors must come from the GGRS theme/layout engine — never hardcoded. */
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
    throw new Error('[GGRS] _parseColor: unrecognized or missing color: ' + JSON.stringify(str));
}

/** Pack [r,g,b,a] (0–1 floats) into u32 big-endian RGBA. */
function _packColorU32(r, g, b, a) {
    return (((Math.round(r * 255) & 0xFF) << 24) |
            ((Math.round(g * 255) & 0xFF) << 16) |
            ((Math.round(b * 255) & 0xFF) << 8) |
            (Math.round(a * 255) & 0xFF)) >>> 0;
}

// ─── Buffer Set ────────────────────────────────────────────────────────────────

/** Holds a chrome (rect) buffer and a growable point buffer. */
class BufferSet {
    constructor() {
        this.chrome = null;    // { buffer: GPUBuffer, count: number }
        this.points = null;    // { buffer: GPUBuffer, count: number, capacity: number }
    }

    destroyChrome() {
        if (this.chrome) {
            this.chrome.buffer.destroy();
            this.chrome = null;
        }
    }

    destroyPoints() {
        if (this.points) {
            this.points.buffer.destroy();
            this.points = null;
        }
    }

    destroy() {
        this.destroyChrome();
        this.destroyPoints();
    }
}

// ─── Constants ─────────────────────────────────────────────────────────────────

const RECT_BYTES_PER_INSTANCE = 32;  // 8 × f32
const POINT_BYTES_PER_INSTANCE = 20; // 2×f32 + f32 + u32 + u32
const INITIAL_POINT_CAPACITY = 100000;
const BUFFER_USAGE = GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC;

// ─── GgrsGpuRenderer ──────────────────────────────────────────────────────────

export class GgrsGpuRenderer {
    constructor() {
        this._device = null;
        this._context = null;
        this._format = null;
        this._canvas = null;

        // Pipelines
        this._rectPipeline = null;
        this._pointPipeline = null;

        // Uniforms
        this._uniformBuffer = null;
        this._uniformBindGroup = null;

        // Buffer sets
        this._active = new BufferSet();
        this._stagingSet = null;   // non-null only during staging
        this._isStaging = false;

        // Canvas logical dimensions
        this._width = 0;
        this._height = 0;

        // Cell step for instant scroll offset
        this.cellStepX = 0;
        this.cellStepY = 0;

        // Clear color
        this._clearColor = { r: 1, g: 1, b: 1, a: 1 };

        // Deferred text: stored during staging, drawn on commit
        this.pendingTexts = null;
        this.pendingTextDpr = 1;

        // Split buffer slots (Phase 1.2 — retained-mode scene graph)
        this._staticChrome = null;     // { buffer: GPUBuffer, count: number }
        this._viewportChrome = null;   // { buffer: GPUBuffer, count: number }
        this._viewportPoints = null;   // { buffer: GPUBuffer, count: number, capacity: number }

        // Second uniform for static rendering (zero scroll offset)
        this._staticUniformBuffer = null;
        this._staticBindGroup = null;

        this._dirty = false;
        this._rafId = null;
    }

    // ── Init ───────────────────────────────────────────────────────────────────

    async init(canvas) {
        if (!navigator.gpu) {
            throw new Error('[GGRS] WebGPU is not available in this browser');
        }
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) {
            throw new Error('[GGRS] WebGPU adapter not available');
        }
        this._device = await adapter.requestDevice();
        this._device.lost.then(info => {
            console.error('[GGRS-GPU] DEVICE LOST:', info.reason, info.message);
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

        // 24 bytes: vec2f canvas_size + vec2f view_translate + vec2f view_scale
        this._uniformBuffer = device.createBuffer({
            size: 24,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });
        // Initialize view_translate=(0,0), view_scale=(1,1)
        device.queue.writeBuffer(
            this._uniformBuffer, 8, new Float32Array([0, 0, 1, 1])
        );

        const bgl = device.createBindGroupLayout({
            entries: [{
                binding: 0,
                visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                buffer: { type: 'uniform' },
            }],
        });

        this._pipelineLayout = device.createPipelineLayout({
            bindGroupLayouts: [bgl],
        });

        this._uniformBindGroup = device.createBindGroup({
            layout: bgl,
            entries: [{
                binding: 0,
                resource: { buffer: this._uniformBuffer },
            }],
        });

        // Static uniform: same layout, identity transform (translate=0,0 scale=1,1)
        this._staticUniformBuffer = device.createBuffer({
            size: 24,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });
        device.queue.writeBuffer(
            this._staticUniformBuffer, 8, new Float32Array([0, 0, 1, 1])
        );
        this._staticBindGroup = device.createBindGroup({
            layout: bgl,
            entries: [{
                binding: 0,
                resource: { buffer: this._staticUniformBuffer },
            }],
        });
    }

    _createPipelines() {
        const device = this._device;
        const format = this._format;
        const layout = this._pipelineLayout;

        const blendState = {
            color: {
                srcFactor: 'src-alpha',
                dstFactor: 'one-minus-src-alpha',
                operation: 'add',
            },
            alpha: {
                srcFactor: 'one',
                dstFactor: 'one-minus-src-alpha',
                operation: 'add',
            },
        };

        // ── Rect pipeline ──────────────────────────────────────────────────────
        const rectModule = device.createShaderModule({ code: RECT_SHADER });
        this._rectPipeline = device.createRenderPipeline({
            layout,
            vertex: {
                module: rectModule,
                entryPoint: 'vs_main',
                buffers: [{
                    arrayStride: RECT_BYTES_PER_INSTANCE,
                    stepMode: 'instance',
                    attributes: [
                        { shaderLocation: 0, offset: 0,  format: 'float32x2' },  // rect_pos
                        { shaderLocation: 1, offset: 8,  format: 'float32x2' },  // rect_size
                        { shaderLocation: 2, offset: 16, format: 'float32x4' },  // color
                    ],
                }],
            },
            fragment: {
                module: rectModule,
                entryPoint: 'fs_main',
                targets: [{ format, blend: blendState }],
            },
            primitive: { topology: 'triangle-strip', stripIndexFormat: 'uint32' },
        });

        // ── Point pipeline ─────────────────────────────────────────────────────
        const pointModule = device.createShaderModule({ code: POINT_SHADER });
        this._pointPipeline = device.createRenderPipeline({
            layout,
            vertex: {
                module: pointModule,
                entryPoint: 'vs_main',
                buffers: [{
                    arrayStride: POINT_BYTES_PER_INSTANCE,
                    stepMode: 'instance',
                    attributes: [
                        { shaderLocation: 0, offset: 0,  format: 'float32x2' },  // center
                        { shaderLocation: 1, offset: 8,  format: 'float32' },    // size
                        { shaderLocation: 2, offset: 12, format: 'uint32' },     // color_packed
                        { shaderLocation: 3, offset: 16, format: 'uint32' },     // shape_idx
                    ],
                }],
            },
            fragment: {
                module: pointModule,
                entryPoint: 'fs_main',
                targets: [{ format, blend: blendState }],
            },
            primitive: { topology: 'triangle-strip', stripIndexFormat: 'uint32' },
        });
    }

    // ── Canvas size ────────────────────────────────────────────────────────────

    setCanvasSize(logicalW, logicalH) {
        this._width = logicalW;
        this._height = logicalH;
        const sizeData = new Float32Array([logicalW, logicalH]);
        this._device.queue.writeBuffer(this._uniformBuffer, 0, sizeData);
        if (this._staticUniformBuffer) {
            this._device.queue.writeBuffer(this._staticUniformBuffer, 0, sizeData);
        }
    }

    // ── View transform ────────────────────────────────────────────────────────

    /**
     * Set the view transform on the viewport uniform buffer.
     * Pre-computes combined translate from zoom origin + pan offset.
     *
     * @param {number} scaleX - Horizontal scale factor
     * @param {number} scaleY - Vertical scale factor
     * @param {number} tx - Pre-computed translate X: originX*(1-scaleX) + panX
     * @param {number} ty - Pre-computed translate Y: originY*(1-scaleY) + panY
     */
    setViewTransform(scaleX, scaleY, tx, ty) {
        this._device.queue.writeBuffer(
            this._uniformBuffer, 8, new Float32Array([tx, ty, scaleX, scaleY])
        );
        this.requestRedraw();
    }

    /** Reset viewport uniform to identity transform (translate=0, scale=1). */
    resetViewTransform() {
        this._device.queue.writeBuffer(
            this._uniformBuffer, 8, new Float32Array([0, 0, 1, 1])
        );
        this.requestRedraw();
    }

    // ── Chrome geometry ────────────────────────────────────────────────────────

    /**
     * Build rect instances from layoutInfo.
     * Writes to staging if in staging mode, otherwise to active.
     */
    setChromeGeometry(layoutInfo) {
        // Update clear color
        if (layoutInfo.plot_background) {
            const [r, g, b, a] = _parseColor(layoutInfo.plot_background);
            this._clearColor = { r, g, b, a };
        }

        // Count instances
        const panels = layoutInfo.panel_backgrounds || [];
        const strips = layoutInfo.strip_backgrounds || [];
        const grids = layoutInfo.grid_lines || [];
        const axes = layoutInfo.axis_lines || [];
        const ticks = layoutInfo.tick_marks || [];
        const borders = layoutInfo.panel_borders || [];

        const instanceCount = panels.length + strips.length
            + grids.length + axes.length + ticks.length
            + borders.length * 4;  // 4 thin rects per border

        if (instanceCount === 0) {
            this._targetSet().destroyChrome();
            return;
        }

        const data = new Float32Array(instanceCount * 8);  // 8 f32 per instance
        let idx = 0;

        const writeRect = (x, y, w, h, color) => {
            const [r, g, b, a] = _parseColor(color);
            const off = idx * 8;
            data[off]     = x;
            data[off + 1] = y;
            data[off + 2] = w;
            data[off + 3] = h;
            data[off + 4] = r;
            data[off + 5] = g;
            data[off + 6] = b;
            data[off + 7] = a;
            idx++;
        };

        // Z-order: panels → strips → grid → axes → ticks → borders
        for (const p of panels) {
            writeRect(p.x, p.y, p.width, p.height, p.fill);
        }
        for (const s of strips) {
            writeRect(s.x, s.y, s.width, s.height, s.fill);
        }
        for (const ln of grids) {
            const r = _lineToRect(ln);
            writeRect(r.x, r.y, r.w, r.h, ln.color);
        }
        for (const ln of axes) {
            const r = _lineToRect(ln);
            writeRect(r.x, r.y, r.w, r.h, ln.color);
        }
        for (const ln of ticks) {
            const r = _lineToRect(ln);
            writeRect(r.x, r.y, r.w, r.h, ln.color);
        }
        for (const pb of borders) {
            if (pb.stroke_width == null) {
                throw new Error('[GGRS] panel_border missing stroke_width');
            }
            const sw = pb.stroke_width;
            // Top edge
            writeRect(pb.x, pb.y, pb.width, sw, pb.color);
            // Bottom edge
            writeRect(pb.x, pb.y + pb.height - sw, pb.width, sw, pb.color);
            // Left edge
            writeRect(pb.x, pb.y + sw, sw, pb.height - 2 * sw, pb.color);
            // Right edge
            writeRect(pb.x + pb.width - sw, pb.y + sw, sw, pb.height - 2 * sw, pb.color);
        }

        // Create GPU buffer
        const target = this._targetSet();
        target.destroyChrome();
        const buffer = this._device.createBuffer({
            size: data.byteLength,
            usage: BUFFER_USAGE,
            mappedAtCreation: true,
        });
        new Float32Array(buffer.getMappedRange()).set(data);
        buffer.unmap();
        target.chrome = { buffer, count: instanceCount };

        // Extract cell step from panel positions
        this._extractCellStep(panels);
    }

    _extractCellStep(panels) {
        if (panels.length < 2) return;
        // Find first panel in a different row (different y)
        for (let i = 1; i < panels.length; i++) {
            if (Math.abs(panels[i].y - panels[0].y) > 0.5) {
                this.cellStepY = panels[i].y - panels[0].y;
                break;
            }
        }
        // Find first panel in a different column (different x)
        for (let i = 1; i < panels.length; i++) {
            if (Math.abs(panels[i].x - panels[0].x) > 0.5) {
                this.cellStepX = panels[i].x - panels[0].x;
                break;
            }
        }
    }

    // ── Rect buffer builder (shared by old + new paths) ────────────────────────

    /** Build a GPUBuffer of rect instances from a layoutInfo-like object.
     *  Returns { buffer, count } or null if no instances. */
    _buildRectBuffer(layoutInfo) {
        const panels = layoutInfo.panel_backgrounds || [];
        const strips = layoutInfo.strip_backgrounds || [];
        const grids = layoutInfo.grid_lines || [];
        const axes = layoutInfo.axis_lines || [];
        const ticks = layoutInfo.tick_marks || [];
        const borders = layoutInfo.panel_borders || [];

        const instanceCount = panels.length + strips.length
            + grids.length + axes.length + ticks.length
            + borders.length * 4;

        if (instanceCount === 0) return null;

        const data = new Float32Array(instanceCount * 8);
        let idx = 0;

        const writeRect = (x, y, w, h, color) => {
            const [r, g, b, a] = _parseColor(color);
            const off = idx * 8;
            data[off]     = x;
            data[off + 1] = y;
            data[off + 2] = w;
            data[off + 3] = h;
            data[off + 4] = r;
            data[off + 5] = g;
            data[off + 6] = b;
            data[off + 7] = a;
            idx++;
        };

        for (const p of panels) writeRect(p.x, p.y, p.width, p.height, p.fill);
        for (const s of strips) writeRect(s.x, s.y, s.width, s.height, s.fill);
        for (const ln of grids) {
            const r = _lineToRect(ln);
            writeRect(r.x, r.y, r.w, r.h, ln.color);
        }
        for (const ln of axes) {
            const r = _lineToRect(ln);
            writeRect(r.x, r.y, r.w, r.h, ln.color);
        }
        for (const ln of ticks) {
            const r = _lineToRect(ln);
            writeRect(r.x, r.y, r.w, r.h, ln.color);
        }
        for (const pb of borders) {
            if (pb.stroke_width == null) {
                throw new Error('[GGRS] panel_border missing stroke_width');
            }
            const sw = pb.stroke_width;
            writeRect(pb.x, pb.y, pb.width, sw, pb.color);
            writeRect(pb.x, pb.y + pb.height - sw, pb.width, sw, pb.color);
            writeRect(pb.x, pb.y + sw, sw, pb.height - 2 * sw, pb.color);
            writeRect(pb.x + pb.width - sw, pb.y + sw, sw, pb.height - 2 * sw, pb.color);
        }

        const buffer = this._device.createBuffer({
            size: data.byteLength,
            usage: BUFFER_USAGE,
            mappedAtCreation: true,
        });
        new Float32Array(buffer.getMappedRange()).set(data);
        buffer.unmap();
        return { buffer, count: instanceCount };
    }

    // ── Static chrome (axes, ticks, column strips — no scroll) ─────────────────

    /** Set static chrome from layout info. Written once per skeleton change. */
    setStaticChrome(layoutInfo) {
        if (layoutInfo.plot_background) {
            const [r, g, b, a] = _parseColor(layoutInfo.plot_background);
            this._clearColor = { r, g, b, a };
        }

        if (this._staticChrome) {
            this._staticChrome.buffer.destroy();
            this._staticChrome = null;
        }

        this._staticChrome = this._buildRectBuffer(layoutInfo);
        this.requestRedraw();
    }

    // ── Viewport chrome (panels, grid, row strips, borders — with scroll) ──────

    /** Set viewport chrome from layout info. Rebuilt on scroll/viewport change. */
    setViewportChrome(layoutInfo) {
        if (this._viewportChrome) {
            this._viewportChrome.buffer.destroy();
            this._viewportChrome = null;
        }

        this._viewportChrome = this._buildRectBuffer(layoutInfo);
        this._extractCellStep(layoutInfo.panel_backgrounds || []);
        this.requestRedraw();
    }

    // ── Viewport points (data — with scroll) ──────────────────────────────────

    /** Replace all viewport points (non-additive). */
    setViewportPoints(points, options) {
        this.clearViewportPoints();
        if (points && points.length > 0) {
            this.appendViewportPoints(points, options);
        }
    }

    /** Append data points to the viewport point buffer (additive / streaming). */
    appendViewportPoints(points, options) {
        if (!points || points.length === 0) return;

        const radius = options.radius;
        const [cr, cg, cb, ca] = _parseColor(options.fillColor);
        const packedColor = _packColorU32(cr, cg, cb, ca);

        const count = points.length;
        const byteSize = count * POINT_BYTES_PER_INSTANCE;
        const buf = new ArrayBuffer(byteSize);
        const f32 = new Float32Array(buf);
        const u32 = new Uint32Array(buf);

        for (let i = 0; i < count; i++) {
            const fi = i * 5;
            f32[fi]     = points[i].px;
            f32[fi + 1] = points[i].py;
            f32[fi + 2] = radius;
            u32[fi + 3] = packedColor;
            u32[fi + 4] = 0;  // shape_idx = circle
        }

        this._appendToViewportPointBuffer(new Uint8Array(buf), count);
        this.requestRedraw();
    }

    _appendToViewportPointBuffer(data, instanceCount) {
        const device = this._device;
        const neededBytes = (this._viewportPoints ? this._viewportPoints.count : 0)
            * POINT_BYTES_PER_INSTANCE + instanceCount * POINT_BYTES_PER_INSTANCE;

        if (!this._viewportPoints) {
            const capacity = Math.max(INITIAL_POINT_CAPACITY, instanceCount);
            const buffer = device.createBuffer({
                size: capacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            device.queue.writeBuffer(buffer, 0, data);
            this._viewportPoints = { buffer, count: instanceCount, capacity };
            return;
        }

        if (this._viewportPoints.count + instanceCount > this._viewportPoints.capacity) {
            const newCapacity = Math.max(
                this._viewportPoints.capacity * 2,
                this._viewportPoints.count + instanceCount
            );
            const newBuffer = device.createBuffer({
                size: newCapacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            const encoder = device.createCommandEncoder();
            encoder.copyBufferToBuffer(
                this._viewportPoints.buffer, 0,
                newBuffer, 0,
                this._viewportPoints.count * POINT_BYTES_PER_INSTANCE
            );
            device.queue.submit([encoder.finish()]);
            this._viewportPoints.buffer.destroy();
            this._viewportPoints.buffer = newBuffer;
            this._viewportPoints.capacity = newCapacity;
        }

        device.queue.writeBuffer(
            this._viewportPoints.buffer,
            this._viewportPoints.count * POINT_BYTES_PER_INSTANCE,
            data
        );
        this._viewportPoints.count += instanceCount;
    }

    clearViewportPoints() {
        if (this._viewportPoints) {
            this._viewportPoints.buffer.destroy();
            this._viewportPoints = null;
        }
    }

    /** Clear viewport chrome + points (called before viewport re-render). */
    clearViewport() {
        if (this._viewportChrome) {
            this._viewportChrome.buffer.destroy();
            this._viewportChrome = null;
        }
        this.clearViewportPoints();
    }

    /** Clear all split buffers (called on binding change / full re-render). */
    clearAll() {
        if (this._staticChrome) {
            this._staticChrome.buffer.destroy();
            this._staticChrome = null;
        }
        this.clearViewport();
    }

    // ── Data points ────────────────────────────────────────────────────────────

    /**
     * Append data points to the point buffer (additive / streaming).
     * Writes to staging if in staging mode, otherwise to active.
     */
    appendDataPoints(points, options) {
        if (!points || points.length === 0) return;

        const radius = options.radius;
        const [cr, cg, cb, ca] = _parseColor(options.fillColor);
        const packedColor = _packColorU32(cr, cg, cb, ca);

        const count = points.length;
        const byteSize = count * POINT_BYTES_PER_INSTANCE;
        const buf = new ArrayBuffer(byteSize);
        const f32 = new Float32Array(buf);
        const u32 = new Uint32Array(buf);

        for (let i = 0; i < count; i++) {
            const fi = i * 5;  // 20 bytes / 4 = 5 u32/f32 slots
            f32[fi]     = points[i].px;
            f32[fi + 1] = points[i].py;
            f32[fi + 2] = radius;
            u32[fi + 3] = packedColor;
            u32[fi + 4] = 0;  // shape_idx = circle
        }

        const target = this._targetSet();
        this._appendToPointBuffer(target, new Uint8Array(buf), count);
    }

    _appendToPointBuffer(target, data, instanceCount) {
        const device = this._device;
        const neededBytes = (target.points ? target.points.count : 0) * POINT_BYTES_PER_INSTANCE
            + instanceCount * POINT_BYTES_PER_INSTANCE;

        if (!target.points) {
            // Create initial buffer
            const capacity = Math.max(INITIAL_POINT_CAPACITY, instanceCount);
            const buffer = device.createBuffer({
                size: capacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            device.queue.writeBuffer(buffer, 0, data);
            target.points = { buffer, count: instanceCount, capacity };
            return;
        }

        // Grow if needed
        if (target.points.count + instanceCount > target.points.capacity) {
            const newCapacity = Math.max(
                target.points.capacity * 2,
                target.points.count + instanceCount
            );
            const newBuffer = device.createBuffer({
                size: newCapacity * POINT_BYTES_PER_INSTANCE,
                usage: BUFFER_USAGE,
            });
            // Copy existing data
            const encoder = device.createCommandEncoder();
            encoder.copyBufferToBuffer(
                target.points.buffer, 0,
                newBuffer, 0,
                target.points.count * POINT_BYTES_PER_INSTANCE
            );
            device.queue.submit([encoder.finish()]);
            target.points.buffer.destroy();
            target.points.buffer = newBuffer;
            target.points.capacity = newCapacity;
        }

        // Write new data
        device.queue.writeBuffer(
            target.points.buffer,
            target.points.count * POINT_BYTES_PER_INSTANCE,
            data
        );
        target.points.count += instanceCount;
    }

    // ── Staging ────────────────────────────────────────────────────────────────

    /** Target buffer set: staging if in staging mode, otherwise active. */
    _targetSet() {
        return this._isStaging ? this._stagingSet : this._active;
    }

    /** Enter staging mode — subsequent writes go to staging buffers. */
    beginStaging() {
        if (this._stagingSet) {
            this._stagingSet.destroy();
        }
        this._stagingSet = new BufferSet();
        this._isStaging = true;
    }

    /** Swap staging → active, reset scroll offset, exit staging mode. */
    commitStaging() {
        if (!this._stagingSet) return;

        // Destroy old active
        this._active.destroy();

        // Promote staging to active
        this._active = this._stagingSet;
        this._stagingSet = null;
        this._isStaging = false;

        // Reset view transform to identity
        this._device.queue.writeBuffer(
            this._uniformBuffer, 8, new Float32Array([0, 0, 1, 1])
        );

        this.requestRedraw();
    }

    // ── Scroll (legacy — kept for commitStaging compat) ─────────────────────

    // ── Render loop ────────────────────────────────────────────────────────────

    requestRedraw() {
        if (this._dirty) return;
        this._dirty = true;
        this._rafId = requestAnimationFrame(() => this._render());
    }

    _render() {
        this._dirty = false;
        this._rafId = null;

        if (!this._device || !this._context) return;

        const texture = this._context.getCurrentTexture();

        const encoder = this._device.createCommandEncoder();
        const pass = encoder.beginRenderPass({
            colorAttachments: [{
                view: texture.createView(),
                clearValue: this._clearColor,
                loadOp: 'clear',
                storeOp: 'store',
            }],
        });

        const hasNewBuffers = this._staticChrome || this._viewportChrome || this._viewportPoints;

        if (hasNewBuffers) {
            // ── Split-buffer path (Phase 1.2+) ─────────────────────────────

            // 1. Viewport chrome: panels, grid, row strips, borders (with scroll)
            if (this._viewportChrome && this._viewportChrome.count > 0) {
                pass.setBindGroup(0, this._uniformBindGroup);
                pass.setPipeline(this._rectPipeline);
                pass.setVertexBuffer(0, this._viewportChrome.buffer);
                pass.draw(4, this._viewportChrome.count);
            }

            // 2. Static chrome: axes, ticks, column strips (no scroll)
            if (this._staticChrome && this._staticChrome.count > 0) {
                pass.setBindGroup(0, this._staticBindGroup);
                pass.setPipeline(this._rectPipeline);
                pass.setVertexBuffer(0, this._staticChrome.buffer);
                pass.draw(4, this._staticChrome.count);
            }

            // 3. Viewport data points (with scroll, topmost)
            if (this._viewportPoints && this._viewportPoints.count > 0) {
                pass.setBindGroup(0, this._uniformBindGroup);
                pass.setPipeline(this._pointPipeline);
                pass.setVertexBuffer(0, this._viewportPoints.buffer);
                pass.draw(4, this._viewportPoints.count);
            }
        } else {
            // ── Legacy path: single buffer set ──────────────────────────────
            pass.setBindGroup(0, this._uniformBindGroup);

            if (this._active.chrome && this._active.chrome.count > 0) {
                pass.setPipeline(this._rectPipeline);
                pass.setVertexBuffer(0, this._active.chrome.buffer);
                pass.draw(4, this._active.chrome.count);
            }

            if (this._active.points && this._active.points.count > 0) {
                pass.setPipeline(this._pointPipeline);
                pass.setVertexBuffer(0, this._active.points.buffer);
                pass.draw(4, this._active.points.count);
            }
        }

        pass.end();
        this._device.queue.submit([encoder.finish()]);
    }

    // ── Cleanup ────────────────────────────────────────────────────────────────

    destroy() {
        if (this._rafId !== null) {
            cancelAnimationFrame(this._rafId);
            this._rafId = null;
        }
        this._active.destroy();
        if (this._stagingSet) {
            this._stagingSet.destroy();
            this._stagingSet = null;
        }
        // Split buffers
        this.clearAll();
        if (this._staticUniformBuffer) {
            this._staticUniformBuffer.destroy();
            this._staticUniformBuffer = null;
        }
        if (this._uniformBuffer) {
            this._uniformBuffer.destroy();
            this._uniformBuffer = null;
        }
        if (this._device) {
            this._device.destroy();
            this._device = null;
        }
        this._context = null;
        this._canvas = null;
    }
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

/** Convert a line {x1,y1,x2,y2,width} to an axis-aligned rect {x,y,w,h}.
 *  Width must come from the GGRS theme — never a hardcoded default. */
function _lineToRect(ln) {
    if (ln.width == null) {
        throw new Error('[GGRS] _lineToRect: line missing width property');
    }
    const lw = ln.width;
    const hw = lw / 2;
    const dx = ln.x2 - ln.x1;
    const dy = ln.y2 - ln.y1;

    if (Math.abs(dy) < 0.001) {
        // Horizontal line
        return {
            x: Math.min(ln.x1, ln.x2),
            y: ln.y1 - hw,
            w: Math.abs(dx),
            h: lw,
        };
    }
    // Vertical or near-vertical line
    return {
        x: ln.x1 - hw,
        y: Math.min(ln.y1, ln.y2),
        w: lw,
        h: Math.abs(dy),
    };
}
*/
