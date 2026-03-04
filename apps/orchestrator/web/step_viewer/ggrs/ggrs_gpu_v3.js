/**
 * WebGPU renderer for GGRS v3 — LayoutState-driven rendering.
 *
 * Key V3 changes:
 * - Reads LayoutState (not ViewState) from uniform buffer
 * - Named layer system for independent chrome updates
 * - Data-space point rendering with GPU projection
 * - No manual sync - LayoutState is single source of truth
 */

// ─── WGSL Shaders ─────────────────────────────────────────────────────────────

/** Chrome rect shader — reads LayoutState for transformations */
const RECT_SHADER_V3 = /* wgsl */`
struct LayoutUniforms {
    canvas_size: vec2f,
    x_range: vec2f,
    y_range: vec2f,
    grid_origin: vec2f,
    cell_size: vec2f,
    cell_spacing: f32,
    n_visible_cols: f32,      // Fractional viewport support
    n_visible_rows: f32,      // Fractional viewport support
    viewport_col_start: f32,  // Fractional viewport support
    viewport_row_start: f32,  // Fractional viewport support
    _pad0: f32,
    scroll_offset: vec2f,
    _pad1: vec2f,
    data_inset_left: f32,     // Space for Y axis chrome
    data_inset_top: f32,      // Space for top chrome
    data_inset_right: f32,    // Space for right padding
    data_inset_bottom: f32,   // Space for X axis chrome
}
@group(0) @binding(0) var<uniform> u_layout: LayoutUniforms;

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
    let pos = rect_pos + corner * rect_size - u_layout.scroll_offset;
    let ndc = vec2f(
        pos.x / u_layout.canvas_size.x * 2.0 - 1.0,
        1.0 - pos.y / u_layout.canvas_size.y * 2.0,
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

/** Data-space point shader — projects using LayoutState */
const POINT_SHADER_V3 = /* wgsl */`
struct LayoutUniforms {
    canvas_size: vec2f,
    x_range: vec2f,
    y_range: vec2f,
    grid_origin: vec2f,
    cell_size: vec2f,
    cell_spacing: f32,
    n_visible_cols: f32,      // Fractional viewport support
    n_visible_rows: f32,      // Fractional viewport support
    viewport_col_start: f32,  // Fractional viewport support
    viewport_row_start: f32,  // Fractional viewport support
    _pad0: f32,
    scroll_offset: vec2f,
    _pad1: vec2f,
    data_inset_left: f32,     // Space for Y axis chrome
    data_inset_top: f32,      // Space for top chrome
    data_inset_right: f32,    // Space for right padding
    data_inset_bottom: f32,   // Space for X axis chrome
}
@group(0) @binding(0) var<uniform> u_layout: LayoutUniforms;

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
    // Compute facet position relative to viewport
    let pc = f32(facet_cr.x) - u_layout.viewport_col_start;
    let pr = f32(facet_cr.y) - u_layout.viewport_row_start;

    // Normalize data to [0,1] within axis range
    let x_span = u_layout.x_range.y - u_layout.x_range.x;
    let y_span = u_layout.y_range.y - u_layout.y_range.x;
    let x_norm = (data_xy.x - u_layout.x_range.x) / x_span;
    let y_norm = (data_xy.y - u_layout.y_range.x) / y_span;

    // Panel position in grid
    let panel_x = u_layout.grid_origin.x + f32(pc) * (u_layout.cell_size.x + u_layout.cell_spacing);
    let panel_y = u_layout.grid_origin.y + f32(pr) * (u_layout.cell_size.y + u_layout.cell_spacing);

    // Data area dimensions (cell minus insets)
    let data_width = u_layout.cell_size.x - u_layout.data_inset_left - u_layout.data_inset_right;
    let data_height = u_layout.cell_size.y - u_layout.data_inset_top - u_layout.data_inset_bottom;

    // Project to pixel coordinates within data area
    let px = panel_x + u_layout.data_inset_left + x_norm * data_width;
    let py = panel_y + u_layout.data_inset_top + (1.0 - y_norm) * data_height;

    // Viewport culling: cull based on PIXEL position, not facet position
    // This allows partially visible facets to render points in visible portion
    if (px < 0.0 || px > u_layout.canvas_size.x || py < 0.0 || py > u_layout.canvas_size.y) {
        var out: VertexOutput;
        out.position = vec4f(0.0, 0.0, 0.0, 0.0);
        out.uv = vec2f(0.0);
        out.color = vec4f(0.0);
        return out;
    }

    // Apply scroll offset
    let screen_pos = vec2f(px, py) - u_layout.scroll_offset;

    // Expand point to quad
    let corner = vec2f(f32(vi & 1u) - 0.5, f32((vi >> 1u) & 1u) - 0.5);
    let expanded = screen_pos + corner * size * 2.0;

    // NDC
    let ndc = vec2f(
        expanded.x / u_layout.canvas_size.x * 2.0 - 1.0,
        1.0 - expanded.y / u_layout.canvas_size.y * 2.0,
    );

    // Unpack color
    let r = f32((color_packed >> 24u) & 0xFFu) / 255.0;
    let g = f32((color_packed >> 16u) & 0xFFu) / 255.0;
    let b = f32((color_packed >> 8u) & 0xFFu) / 255.0;
    let a = f32(color_packed & 0xFFu) / 255.0;

    var out: VertexOutput;
    out.position = vec4f(ndc, 0.0, 1.0);
    out.uv = corner;
    out.color = vec4f(r, g, b, a);
    return out;
}

@fragment
fn fs_main(@location(0) uv: vec2f, @location(1) color: vec4f) -> @location(0) vec4f {
    // SDF circle
    let dist = length(uv);
    let alpha = 1.0 - smoothstep(0.9, 1.0, dist);
    return vec4f(color.rgb, color.a * alpha);
}
`;

// ─── Constants ─────────────────────────────────────────────────────────────────

const RECT_BYTES_PER_INSTANCE = 32;
const POINT_BYTES_PER_INSTANCE = 24;
const INITIAL_POINT_CAPACITY = 100000;
const BUFFER_USAGE = GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST;
const LAYOUT_UNIFORM_SIZE = 96; // 24 floats: 20 from V2 + 4 data insets

// ─── GgrsGpuV3 ────────────────────────────────────────────────────────────────

export class GgrsGpuV3 {
    constructor() {
        this._device = null;
        this._context = null;
        this._format = null;
        this._canvas = null;

        // Pipelines
        this._rectPipeline = null;
        this._pointPipeline = null;

        // Shared LayoutState uniform buffer
        this._layoutUniformBuffer = null;
        this._rectBindGroup = null;
        this._pointBindGroup = null;

        // Named layers for chrome (ordered Map)
        this._layers = new Map();

        // Data point buffer
        this._pointBuffer = null; // { buffer, count, capacity }

        // Canvas size
        this._width = 0;
        this._height = 0;

        // Cached LayoutState (for interaction handlers to read)
        this._layoutState = null;

        // Deferred render
        this._dirty = false;
        this._rafId = null;
    }

    // ── Init ───────────────────────────────────────────────────────────────────

    async init(canvas) {
        console.log('[GgrsGpuV3] init() START');
        console.log('[GgrsGpuV3] Canvas element:', canvas);
        console.log('[GgrsGpuV3] Canvas ID:', canvas.id);
        console.log('[GgrsGpuV3] Canvas size:', canvas.width, 'x', canvas.height);
        console.log('[GgrsGpuV3] Canvas client size:', canvas.clientWidth, 'x', canvas.clientHeight);

        if (!navigator.gpu) {
            throw new Error('[GgrsGpuV3] WebGPU not supported');
        }
        console.log('[GgrsGpuV3] ✓ WebGPU supported');

        this._canvas = canvas;
        const adapter = await navigator.gpu.requestAdapter();
        if (!adapter) {
            throw new Error('[GgrsGpuV3] No WebGPU adapter');
        }
        console.log('[GgrsGpuV3] ✓ WebGPU adapter obtained');

        this._device = await adapter.requestDevice();
        console.log('[GgrsGpuV3] ✓ WebGPU device obtained');

        this._context = canvas.getContext('webgpu');
        console.log('[GgrsGpuV3] ✓ WebGPU context obtained');

        this._format = navigator.gpu.getPreferredCanvasFormat();
        console.log('[GgrsGpuV3] ✓ Canvas format:', this._format);

        this._context.configure({
            device: this._device,
            format: this._format,
            alphaMode: 'premultiplied',
        });
        console.log('[GgrsGpuV3] ✓ Context configured');

        console.log('[GgrsGpuV3] WebGPU initialized');

        // Create pipelines
        await this._createPipelines();

        // Create uniform buffer
        this._layoutUniformBuffer = this._device.createBuffer({
            size: LAYOUT_UNIFORM_SIZE,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
        });

        // Create bind groups
        this._rectBindGroup = this._device.createBindGroup({
            layout: this._rectPipeline.getBindGroupLayout(0),
            entries: [{ binding: 0, resource: { buffer: this._layoutUniformBuffer } }],
        });

        this._pointBindGroup = this._device.createBindGroup({
            layout: this._pointPipeline.getBindGroupLayout(0),
            entries: [{ binding: 0, resource: { buffer: this._layoutUniformBuffer } }],
        });

        console.log('[GgrsGpuV3] Pipelines and buffers ready');
    }

    async _createPipelines() {
        // Rect pipeline
        const rectShaderModule = this._device.createShaderModule({ code: RECT_SHADER_V3 });
        this._rectPipeline = this._device.createRenderPipeline({
            layout: 'auto',
            vertex: {
                module: rectShaderModule,
                entryPoint: 'vs_main',
                buffers: [{
                    arrayStride: RECT_BYTES_PER_INSTANCE,
                    stepMode: 'instance',  // Per-instance data, not per-vertex!
                    attributes: [
                        { shaderLocation: 0, offset: 0, format: 'float32x2' },  // rect_pos
                        { shaderLocation: 1, offset: 8, format: 'float32x2' },  // rect_size
                        { shaderLocation: 2, offset: 16, format: 'float32x4' }, // color
                    ],
                }],
            },
            fragment: {
                module: rectShaderModule,
                entryPoint: 'fs_main',
                targets: [{ format: this._format, blend: {
                    color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' },
                    alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' },
                }}],
            },
            primitive: { topology: 'triangle-strip', stripIndexFormat: 'uint32' },
        });

        // Point pipeline
        const pointShaderModule = this._device.createShaderModule({ code: POINT_SHADER_V3 });
        this._pointPipeline = this._device.createRenderPipeline({
            layout: 'auto',
            vertex: {
                module: pointShaderModule,
                entryPoint: 'vs_main',
                buffers: [{
                    arrayStride: POINT_BYTES_PER_INSTANCE,
                    stepMode: 'instance',  // Per-instance data, not per-vertex!
                    attributes: [
                        { shaderLocation: 0, offset: 0, format: 'float32x2' },  // data_xy
                        { shaderLocation: 1, offset: 8, format: 'uint32x2' },   // facet_cr
                        { shaderLocation: 2, offset: 16, format: 'uint32' },    // color_packed
                        { shaderLocation: 3, offset: 20, format: 'float32' },   // size
                    ],
                }],
            },
            fragment: {
                module: pointShaderModule,
                entryPoint: 'fs_main',
                targets: [{ format: this._format, blend: {
                    color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' },
                    alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' },
                }}],
            },
            primitive: { topology: 'triangle-strip', stripIndexFormat: 'uint32' },
        });
    }

    // ── Layout State Sync ──────────────────────────────────────────────────────

    syncLayoutState(layoutStateJson) {
        const state = JSON.parse(layoutStateJson);

        // Check if layout actually changed (PlotState controls rendering)
        // This prevents infinite render loops and unnecessary GPU work
        const prevState = this._layoutState;
        const changed = !prevState ||
            prevState.vis_x_min !== state.vis_x_min ||
            prevState.vis_x_max !== state.vis_x_max ||
            prevState.vis_y_min !== state.vis_y_min ||
            prevState.vis_y_max !== state.vis_y_max ||
            prevState.grid_origin_x !== state.grid_origin_x ||
            prevState.grid_origin_y !== state.grid_origin_y ||
            prevState.cell_width !== state.cell_width ||
            prevState.cell_height !== state.cell_height ||
            prevState.cell_spacing !== state.cell_spacing ||
            prevState.n_visible_cols !== state.n_visible_cols ||
            prevState.n_visible_rows !== state.n_visible_rows ||
            prevState.viewport_col_start !== state.viewport_col_start ||
            prevState.viewport_row_start !== state.viewport_row_start ||
            (prevState.scroll_offset_x || 0) !== (state.scroll_offset_x || 0) ||
            (prevState.scroll_offset_y || 0) !== (state.scroll_offset_y || 0) ||
            (prevState.data_inset_left || 0) !== (state.data_inset_left || 0) ||
            (prevState.data_inset_top || 0) !== (state.data_inset_top || 0) ||
            (prevState.data_inset_right || 0) !== (state.data_inset_right || 0) ||
            (prevState.data_inset_bottom || 0) !== (state.data_inset_bottom || 0);

        if (!changed) {
            // No change - don't write buffer, don't trigger redraw
            return;
        }

        this._layoutState = state;

        // Write 96-byte uniform buffer (24 floats)
        const data = new Float32Array(24);
        data[0] = this._width;
        data[1] = this._height;
        data[2] = state.vis_x_min;
        data[3] = state.vis_x_max;
        data[4] = state.vis_y_min;
        data[5] = state.vis_y_max;
        data[6] = state.grid_origin_x;
        data[7] = state.grid_origin_y;
        data[8] = state.cell_width;
        data[9] = state.cell_height;
        data[10] = state.cell_spacing;

        // Fractional viewport fields (f32)
        data[11] = state.n_visible_cols;
        data[12] = state.n_visible_rows;
        data[13] = state.viewport_col_start || 0;
        data[14] = state.viewport_row_start || 0;
        data[15] = 0; // _pad0
        data[16] = state.scroll_offset_x || 0;
        data[17] = state.scroll_offset_y || 0;
        data[18] = 0; // _pad1.x
        data[19] = 0; // _pad1.y

        // Data insets (space for axis chrome)
        data[20] = state.data_inset_left || 0;
        data[21] = state.data_inset_top || 0;
        data[22] = state.data_inset_right || 0;
        data[23] = state.data_inset_bottom || 0;

        this._device.queue.writeBuffer(this._layoutUniformBuffer, 0, data.buffer);
        this.requestRedraw();

        console.log('[GgrsGpuV3] LayoutState synced (changed):', {
            x_range: [state.vis_x_min, state.vis_x_max],
            y_range: [state.vis_y_min, state.vis_y_max],
            cell_size: [state.cell_width, state.cell_height],
            visible: [state.n_visible_cols, state.n_visible_rows],
            viewport: [state.viewport_col_start, state.viewport_row_start],
            scroll_offset: [state.scroll_offset_x || 0, state.scroll_offset_y || 0],
            data_insets: [state.data_inset_left, state.data_inset_top, state.data_inset_right, state.data_inset_bottom],
        });
    }

    /**
     * Get current layout state (read-only snapshot).
     * Used by InteractionManager for zone detection.
     * @returns {object|null} Layout state object or null if not initialized
     */
    getLayoutState() {
        return this._layoutState;
    }

    // ── Named Layer Management ─────────────────────────────────────────────────

    setLayer(name, rects) {
        if (!rects || rects.length === 0) {
            this._layers.delete(name);
            this.requestRedraw();
            return;
        }

        const count = rects.length;
        const byteLength = count * RECT_BYTES_PER_INSTANCE;

        const buffer = this._device.createBuffer({
            size: byteLength,
            usage: BUFFER_USAGE,
            mappedAtCreation: true,
        });

        const data = new Float32Array(buffer.getMappedRange());
        for (let i = 0; i < count; i++) {
            const r = rects[i];
            const offset = i * 8;
            data[offset + 0] = r.x;
            data[offset + 1] = r.y;
            data[offset + 2] = r.w;
            data[offset + 3] = r.h;
            data[offset + 4] = r.color[0];
            data[offset + 5] = r.color[1];
            data[offset + 6] = r.color[2];
            data[offset + 7] = r.color[3];
        }
        buffer.unmap();

        this._layers.set(name, { buffer, count });
        this.requestRedraw();

        console.log(`[GgrsGpuV3] Layer '${name}' set: ${count} rects`);
    }

    clearLayer(name) {
        this._layers.delete(name);
        this.requestRedraw();
    }

    // ── Data Points ────────────────────────────────────────────────────────────

    setDataPoints(points) {
        if (!points || points.length === 0) {
            this._pointBuffer = null;
            this.requestRedraw();
            return;
        }

        const count = points.length;
        const byteLength = count * POINT_BYTES_PER_INSTANCE;

        const buffer = this._device.createBuffer({
            size: byteLength,
            usage: BUFFER_USAGE,
            mappedAtCreation: true,
        });

        const arrayBuffer = buffer.getMappedRange();
        const f32 = new Float32Array(arrayBuffer);
        const u32 = new Uint32Array(arrayBuffer);

        for (let i = 0; i < count; i++) {
            const p = points[i];
            const f32_offset = i * 6;
            const u32_offset = i * 6;

            f32[f32_offset + 0] = p.x;
            f32[f32_offset + 1] = p.y;
            u32[u32_offset + 2] = p.ci || 0;
            u32[u32_offset + 3] = p.ri || 0;
            u32[u32_offset + 4] = p.color_packed || 0xFF0000FF; // default red
            f32[f32_offset + 5] = p.size || 3.0;
        }
        buffer.unmap();

        this._pointBuffer = { buffer, count };
        this._allPoints = points;  // Store for appendDataPoints()
        this.requestRedraw();

        console.log(`[GgrsGpuV3] Data points set: ${count}`);
    }

    appendDataPoints(newPoints) {
        if (!newPoints || newPoints.length === 0) {
            return;
        }

        // Get existing points or empty array
        const existingPoints = this._allPoints || [];

        // Append new points
        const allPoints = [...existingPoints, ...newPoints];

        // Store for future appends
        this._allPoints = allPoints;

        // Update GPU buffer
        this.setDataPoints(allPoints);

        console.log(`[GgrsGpuV3] Data points appended: +${newPoints.length} (total: ${allPoints.length})`);
    }

    clearDataPoints() {
        this._allPoints = [];
        this._pointBuffer = null;
        this.requestRedraw();
        console.log(`[GgrsGpuV3] Data points cleared`);
    }

    // ── Render ─────────────────────────────────────────────────────────────────

    resize(width, height) {
        console.log(`[GgrsGpuV3] resize(${width}, ${height}) - DPR: ${devicePixelRatio}`);
        this._width = width;
        this._height = height;
        this._canvas.width = width * devicePixelRatio;
        this._canvas.height = height * devicePixelRatio;
        this._canvas.style.width = `${width}px`;
        this._canvas.style.height = `${height}px`;
        console.log(`[GgrsGpuV3] Canvas resized to ${this._canvas.width}x${this._canvas.height} (buffer), ${width}x${height} (CSS)`);
        this.requestRedraw();
    }

    requestRedraw() {
        if (this._dirty) {
            console.log('[GgrsGpuV3] requestRedraw() - already dirty, skipping');
            return;
        }
        console.log('[GgrsGpuV3] requestRedraw() - scheduling render');
        this._dirty = true;
        this._rafId = requestAnimationFrame(() => this._render());
    }

    _render() {
        this._dirty = false;
        console.log('[GgrsGpuV3] ========== _render() START ==========');
        console.log('[GgrsGpuV3] Layers:', this._layers.size, 'Points:', this._pointBuffer?.count || 0);
        console.log('[GgrsGpuV3] Canvas:', this._canvas?.width, 'x', this._canvas?.height);
        console.log('[GgrsGpuV3] Device:', this._device ? 'OK' : 'NULL');
        console.log('[GgrsGpuV3] Context:', this._context ? 'OK' : 'NULL');

        const encoder = this._device.createCommandEncoder();
        console.log('[GgrsGpuV3] ✓ Command encoder created');

        const textureView = this._context.getCurrentTexture().createView();
        console.log('[GgrsGpuV3] ✓ Texture view created');

        const renderPass = encoder.beginRenderPass({
            colorAttachments: [{
                view: textureView,
                loadOp: 'clear',
                clearValue: { r: 1, g: 1, b: 1, a: 1 },
                storeOp: 'store',
            }],
        });
        console.log('[GgrsGpuV3] ✓ Render pass started (white clear)');

        // Draw chrome layers (ordered by insertion)
        renderPass.setPipeline(this._rectPipeline);
        renderPass.setBindGroup(0, this._rectBindGroup);
        console.log('[GgrsGpuV3] ✓ Rect pipeline set');

        let layerCount = 0;
        for (const [name, layer] of this._layers) {
            console.log(`[GgrsGpuV3]   Drawing layer '${name}': ${layer.count} rects`);
            renderPass.setVertexBuffer(0, layer.buffer);
            renderPass.draw(4, layer.count);
            layerCount++;
        }
        console.log(`[GgrsGpuV3] ✓ Drew ${layerCount} chrome layers`);

        // Draw data points
        if (this._pointBuffer) {
            console.log(`[GgrsGpuV3] Drawing ${this._pointBuffer.count} data points`);
            renderPass.setPipeline(this._pointPipeline);
            renderPass.setBindGroup(0, this._pointBindGroup);
            renderPass.setVertexBuffer(0, this._pointBuffer.buffer);
            renderPass.draw(4, this._pointBuffer.count);
            console.log('[GgrsGpuV3] ✓ Data points drawn');
        } else {
            console.log('[GgrsGpuV3] ⚠ No point buffer');
        }

        renderPass.end();
        console.log('[GgrsGpuV3] ✓ Render pass ended');

        this._device.queue.submit([encoder.finish()]);
        console.log('[GgrsGpuV3] ========== _render() COMPLETE - frame submitted ==========');
    }

    // ── Cleanup ────────────────────────────────────────────────────────────────

    destroy() {
        if (this._rafId) cancelAnimationFrame(this._rafId);
        this._layoutUniformBuffer?.destroy();
        for (const layer of this._layers.values()) {
            layer.buffer?.destroy();
        }
        this._pointBuffer?.buffer?.destroy();
        this._device?.destroy();
    }
}
