/**
 * RenderCoordinator - Layer-based orchestration for V3.
 *
 * Key concepts:
 * - Layers declare dependencies (e.g., DataLayer depends on ChromeLayers)
 * - Coordinator runs layers in dependency order
 * - Each layer can invalidate independently
 * - Pull-based: coordinator checks which layers need rendering
 */

// ─── RenderLayer Base Class ────────────────────────────────────────────────

export class RenderLayer {
    constructor(name, priority) {
        this.name = name;
        this.priority = priority; // Lower number = higher priority (render first)
        this.generation = 0;
        this.state = 'idle'; // idle | rendering | complete | failed
        this.dependencies = []; // Array of layer names this depends on
        this.lastRenderTime = 0;
        this.error = null;
    }

    /**
     * Check if layer needs rendering
     * @returns {boolean}
     */
    isStale() {
        return this.state !== 'complete';
    }

    /**
     * Check if dependencies are met
     * @param {RenderContext} ctx
     * @returns {boolean}
     */
    canRender(ctx) {
        // Check all dependencies are complete
        for (const depName of this.dependencies) {
            const depLayer = ctx.coordinator.getLayer(depName);
            if (!depLayer || depLayer.state !== 'complete') {
                return false;
            }
        }
        return true;
    }

    /**
     * Render this layer
     * @param {RenderContext} ctx
     * @returns {Promise<void>}
     */
    async render(ctx) {
        throw new Error(`${this.name}: render() not implemented`);
    }

    /**
     * Invalidate this layer (mark for re-render)
     */
    invalidate() {
        this.generation++;
        this.state = 'idle';
        this.error = null;
    }

    /**
     * Cancel active rendering
     */
    cancel() {
        if (this.state === 'rendering') {
            this.state = 'idle';
        }
    }
}

// ─── RenderContext ─────────────────────────────────────────────────────────

class RenderContext {
    constructor(coordinator) {
        this.coordinator = coordinator;
        this.containerId = null;
        this.renderer = null; // WASM renderer
        this.gpu = null; // GgrsGpuV3
        this.width = 0;
        this.height = 0;
        this.textMeasurer = null;

        // Snapshots from layers
        this.layoutStateJson = null;
        this.chromeJson = null;
    }

    getLayer(name) {
        return this.coordinator.getLayer(name);
    }
}

// ─── Concrete Layer Implementations ────────────────────────────────────────

/**
 * LayoutLayer - Calls getStreamLayout and caches LayoutInfo
 */
export class LayoutLayer extends RenderLayer {
    constructor(renderer, width, height, textMeasurer) {
        super('layout', 10);
        this.renderer = renderer;
        this.width = width;
        this.height = height;
        this.textMeasurer = textMeasurer;
        this.layoutInfo = null;
    }

    isStale() {
        return this.layoutInfo === null || this.state !== 'complete';
    }

    async render(ctx) {
        console.log('[LayoutLayer] Computing layout...');
        const layoutInfoJson = this.renderer.getStreamLayout(
            this.width,
            this.height,
            '', // viewport_json
            this.textMeasurer
        );

        const layoutInfo = JSON.parse(layoutInfoJson);
        if (layoutInfo.error) {
            throw new Error(`Layout failed: ${layoutInfo.error}`);
        }

        this.layoutInfo = layoutInfo;
        ctx.layoutInfo = layoutInfo; // Share with other layers
        this.state = 'complete';
        console.log('[LayoutLayer] Complete');
    }
}

/**
 * ViewStateLayer - Calls initView to create ViewState
 *
 * NOTE: Currently uses ViewState (initView) approach.
 * Future: migrate to LayoutManager (initLayout) when PlotDimensions is exposed in LayoutInfo.
 * LayoutManager provides better zoom/pan state management but requires PlotDimensions struct
 * which is internal to compute_layout_info and not currently serialized.
 */
export class ViewStateLayer extends RenderLayer {
    constructor(renderer) {
        super('viewstate', 15);
        this.dependencies = ['layout'];
        this.renderer = renderer;
    }

    async render(ctx) {
        console.log('[ViewStateLayer] Creating ViewState...');
        const layoutInfo = ctx.layoutInfo;
        if (!layoutInfo) {
            throw new Error('ViewStateLayer: no layoutInfo');
        }

        // Extract geometry for initView (ViewState approach)
        // Axis ranges from metadata (stored in coordinator context)

        // Validate panels array exists and has at least one panel
        if (!layoutInfo.panels || layoutInfo.panels.length === 0) {
            throw new Error('ViewStateLayer: layoutInfo.panels is empty or undefined');
        }

        // Validate required context fields (no silent undefined → 0.0 conversions)
        const requiredFields = ['xMin', 'xMax', 'yMin', 'yMax', 'dataXMin', 'dataXMax', 'dataYMin', 'dataYMax'];
        for (const field of requiredFields) {
            if (ctx[field] === undefined || ctx[field] === null) {
                throw new Error(`ViewStateLayer: missing required context field '${field}'`);
            }
        }

        // Call computeSkeleton first (required before initView/getViewChrome)
        const viewportJson = JSON.stringify({
            ci_min: 0,
            ci_max: (ctx.nColFacets || 1) - 1,
            ri_min: 0,
            ri_max: (ctx.nRowFacets || 1) - 1,
        });
        window.ggrsComputeSkeleton(
            this.renderer,
            ctx.width,
            ctx.height,
            viewportJson,
            ctx.textMeasurer
        );
        console.log('[ViewStateLayer] computeSkeleton called');

        const viewParams = {
            full_x_min: ctx.xMin,
            full_x_max: ctx.xMax,
            full_y_min: ctx.yMin,
            full_y_max: ctx.yMax,
            data_x_min: ctx.dataXMin,
            data_x_max: ctx.dataXMax,
            data_y_min: ctx.dataYMin,
            data_y_max: ctx.dataYMax,
            canvas_width: layoutInfo.width,
            canvas_height: layoutInfo.height,
            // Extract from first panel
            grid_origin_x: layoutInfo.panels[0].x,
            grid_origin_y: layoutInfo.panels[0].y,
            cell_width: layoutInfo.panels[0].width,
            cell_height: layoutInfo.panels[0].height,
            cell_spacing: 10, // TODO: get from layout
            n_visible_cols: ctx.nColFacets || 1,
            n_visible_rows: ctx.nRowFacets || 1,
        };

        const viewSnapshot = this.renderer.initView(JSON.stringify(viewParams));
        ctx.viewSnapshot = viewSnapshot;
        this.state = 'complete';
        console.log('[ViewStateLayer] Complete');
    }
}

/**
 * ChromeLayer - Renders a single chrome category
 */
export class ChromeLayer extends RenderLayer {
    constructor(category, gpu, renderer) {
        super(`chrome:${category}`, 30);
        this.dependencies = ['viewstate'];
        this.category = category;
        this.gpu = gpu;
        this.renderer = renderer;
    }

    async render(ctx) {
        console.log(`[ChromeLayer:${this.category}] Rendering...`);

        // Cache chrome JSON in context (first layer fetches, others reuse)
        if (!ctx.chromeCache) {
            const chromeJson = this.renderer.getViewChrome();
            ctx.chromeCache = JSON.parse(chromeJson);
            console.log(`[ChromeLayer:${this.category}] Fetched chrome from WASM (cached for other layers)`);

            if (ctx.chromeCache.error) {
                throw new Error(`Chrome failed: ${ctx.chromeCache.error}`);
            }
        }

        // Extract this category from cached chrome
        const elements = ctx.chromeCache[this.category];
        if (!elements || elements.length === 0) {
            this.state = 'complete';
            return;
        }

        // Convert to GPU rects
        // Note: backgrounds use 'fill', lines/borders use 'color'
        const rects = elements.map(elem => ({
            x: elem.x,
            y: elem.y,
            w: elem.width,
            h: elem.height,
            color: this._parseColor(elem.fill || elem.color),
        }));

        this.gpu.setLayer(this.category, rects);
        this.state = 'complete';
        console.log(`[ChromeLayer:${this.category}] Complete: ${rects.length} rects`);
    }

    _parseColor(str) {
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
        // NO FALLBACK - throw error to surface bad data
        throw new Error(`ChromeLayer: Invalid color format '${str}' (expected #RRGGBB, #RRGGBBAA, rgb(), or rgba())`);
    }
}

/**
 * DataLayer - Streams data points from WASM
 */
export class DataLayer extends RenderLayer {
    constructor(gpu, renderer, chunkSize) {
        super('data:points', 60);
        this.dependencies = [
            'chrome:panel_backgrounds',
            'chrome:strip_backgrounds',
            'chrome:grid_lines',
            'chrome:axis_lines',
            'chrome:tick_marks',
            'chrome:panel_borders'
        ];
        this.gpu = gpu;
        this.renderer = renderer;
        this.chunkSize = chunkSize;
        this.streamToken = 0;
    }

    async render(ctx) {
        console.log('[DataLayer] Streaming data...');
        const currentToken = ++this.streamToken;
        const allPoints = [];
        let done = false;

        while (!done) {
            // Check if cancelled
            if (this.streamToken !== currentToken) {
                console.log('[DataLayer] Cancelled');
                return;
            }

            const resultJson = await this.renderer.loadDataChunk(this.chunkSize);
            const result = JSON.parse(resultJson);

            if (result.error) {
                throw new Error(`Data chunk error: ${result.error}`);
            }

            allPoints.push(...result.points);
            done = result.done;

            console.log(`[DataLayer] Loaded ${result.loaded}/${result.total}`);
        }

        // Pack for GPU
        const gpuPoints = allPoints.map(p => ({
            x: p.x,
            y: p.y,
            ci: p.ci,
            ri: p.ri,
            color_packed: this._packColorU32(0.2, 0.4, 0.8, 0.8),
            size: 3.0,
        }));

        this.gpu.setDataPoints(gpuPoints);
        this.state = 'complete';
        console.log(`[DataLayer] Complete: ${allPoints.length} points`);
    }

    cancel() {
        super.cancel();
        this.streamToken++; // Abort active stream
    }

    _packColorU32(r, g, b, a) {
        return (
            ((Math.round(r * 255) & 0xFF) << 24) |
            ((Math.round(g * 255) & 0xFF) << 16) |
            ((Math.round(b * 255) & 0xFF) << 8) |
            (Math.round(a * 255) & 0xFF)
        ) >>> 0;
    }
}

// ─── RenderCoordinator ─────────────────────────────────────────────────────

export class RenderCoordinator {
    constructor() {
        this.layers = new Map();
        this.context = new RenderContext(this);
        this.renderLoopActive = false;
        this.listeners = [];
        this.generation = 0; // For cancelling stale renders
    }

    registerLayer(layer) {
        this.layers.set(layer.name, layer);
    }

    getLayer(name) {
        return this.layers.get(name);
    }

    /**
     * Invalidate specific layers
     */
    invalidateLayers(names) {
        for (const name of names) {
            const layer = this.layers.get(name);
            if (layer) {
                layer.cancel();
                layer.invalidate();
            }
        }
        this._scheduleRenderLoop();
    }

    /**
     * Invalidate all layers
     */
    invalidateAll() {
        // Clear chrome cache when invalidating all
        this.context.chromeCache = null;

        for (const layer of this.layers.values()) {
            layer.cancel();
            layer.invalidate();
        }
        this._scheduleRenderLoop();
    }

    /**
     * Update context and invalidate dependent layers
     */
    updateContext(updates) {
        Object.assign(this.context, updates);

        // Cascade invalidation based on what changed
        if (updates.renderer || updates.width || updates.height) {
            this.invalidateAll();
        } else if (updates.xMin !== undefined || updates.dataXMin !== undefined) {
            // Axis ranges changed - invalidate viewstate and downstream
            // Clear chrome cache since ranges affect chrome geometry
            this.context.chromeCache = null;
            this.invalidateLayers(['viewstate']);
            this._invalidateDependents('viewstate');
        }
    }

    _invalidateDependents(layerName) {
        for (const layer of this.layers.values()) {
            if (layer.dependencies.includes(layerName)) {
                layer.invalidate();
                this._invalidateDependents(layer.name); // Recursive
            }
        }
    }

    _scheduleRenderLoop() {
        if (this.renderLoopActive) return;
        this.renderLoopActive = true;
        requestAnimationFrame(() => this._renderLoop());
    }

    async _renderLoop() {
        // Capture current generation for cancellation checking
        const currentGen = ++this.generation;

        while (true) {
            // Check if render has been cancelled
            if (this.generation !== currentGen) {
                console.log('[RenderCoordinator] Render cancelled (stale generation)');
                this.renderLoopActive = false;
                return;
            }

            const layer = this._findNextLayer();
            if (!layer) {
                this.renderLoopActive = false;
                this._notifyComplete();
                return;
            }

            layer.state = 'rendering';
            this._notifyProgress(layer.name, 'rendering');

            try {
                await layer.render(this.context);
                this._notifyProgress(layer.name, 'complete');
            } catch (e) {
                layer.state = 'failed';
                layer.error = e.toString();
                console.error(`[RenderCoordinator] Layer ${layer.name} failed:`, e);
                console.error(`[RenderCoordinator] Error message: ${e.message}`);
                console.error(`[RenderCoordinator] Error stack:`, e.stack);
                this._notifyProgress(layer.name, 'failed');
            }

            // Yield to browser
            await new Promise(resolve => requestAnimationFrame(resolve));
        }
    }

    _findNextLayer() {
        let best = null;
        let bestPriority = Infinity;

        for (const layer of this.layers.values()) {
            if (layer.isStale() &&
                layer.state !== 'rendering' &&
                layer.state !== 'failed' &&
                layer.canRender(this.context) &&
                layer.priority < bestPriority) {
                best = layer;
                bestPriority = layer.priority;
            }
        }

        return best;
    }

    /**
     * Cancel active render by incrementing generation counter.
     * Called by Dart when starting a new render.
     */
    cancelRender() {
        this.generation++;
        console.log('[RenderCoordinator] Cancelling active render (new generation)');
        // Also cancel all active layer renders
        for (const layer of this.layers.values()) {
            if (layer.state === 'rendering') {
                layer.cancel();
            }
        }
    }

    addListener(fn) {
        this.listeners.push(fn);
    }

    /**
     * Remove all progress listeners.
     * Called during cleanup to prevent memory leaks.
     */
    removeAllListeners() {
        this.listeners = [];
    }

    _notifyProgress(layerName, status) {
        for (const listener of this.listeners) {
            listener({ layer: layerName, status });
        }
    }

    _notifyComplete() {
        for (const listener of this.listeners) {
            listener({ complete: true });
        }
    }
}
