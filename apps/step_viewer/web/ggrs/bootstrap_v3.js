// GGRS V3 Bootstrap - Viewport-driven rendering (aligned with test_streaming.html)

import init, { GGRSRenderer } from "./pkg/ggrs_wasm.js";
import { GgrsGpuV3 } from "./ggrs_gpu_v3.js";
import { PlotState } from "./plot_state.js";
import { InteractionManager } from "./interaction_manager.js";
import { PlotOrchestrator } from "./plot_orchestrator.js";

// WASM initialization state
let wasmInitialized = false;
let wasmInitPromise = null;

/**
 * Ensure WASM is initialized (idempotent)
 */
async function ensureWasmInitialized() {
  if (wasmInitialized) return;
  if (wasmInitPromise) return wasmInitPromise;

  console.log('[bootstrap_v3] Starting WASM initialization...');
  wasmInitPromise = init()
    .then(() => {
      wasmInitialized = true;
      console.log('[bootstrap_v3] WASM initialized successfully');
    })
    .catch((e) => {
      console.error('[bootstrap_v3] WASM initialization failed:', e);
      wasmInitPromise = null;
      throw e;
    });

  return wasmInitPromise;
}

/**
 * Create a WASM renderer instance
 */
function createRenderer(containerId) {
  if (!wasmInitialized) {
    throw new Error('WASM not initialized. Call ensureWasmInitialized() first.');
  }
  console.log(`[bootstrap_v3] Creating renderer for ${containerId}`);
  return new GGRSRenderer(containerId);
}

// ─── Helper Functions ──────────────────────────────────────────────────────

function _parseColor(str) {
  if (str && str.startsWith('#')) {
    const hex = str.slice(1);
    if (hex.length === 6) {
      return [
        parseInt(hex.slice(0, 2), 16) / 255,
        parseInt(hex.slice(2, 4), 16) / 255,
        parseInt(hex.slice(4, 6), 16) / 255,
        1.0,
      ];
    } else if (hex.length === 8) {
      return [
        parseInt(hex.slice(0, 2), 16) / 255,
        parseInt(hex.slice(2, 4), 16) / 255,
        parseInt(hex.slice(4, 6), 16) / 255,
        parseInt(hex.slice(6, 8), 16) / 255,
      ];
    }
  }
  if (str && str.startsWith('rgb(')) {
    const parts = str.slice(4, -1).split(',').map(s => s.trim());
    return [
      parseInt(parts[0]) / 255,
      parseInt(parts[1]) / 255,
      parseInt(parts[2]) / 255,
      1.0,
    ];
  }
  return [0.5, 0.5, 0.5, 1.0];
}

function _packColorU32(r, g, b, a) {
  return (
    ((Math.round(r * 255) & 0xFF) << 24) |
    ((Math.round(g * 255) & 0xFF) << 16) |
    ((Math.round(b * 255) & 0xFF) << 8) |
    (Math.round(a * 255) & 0xFF)
  ) >>> 0;
}

// ─── Chrome rendering helpers ─────────────────────────────────────────────

/**
 * Apply chrome rect layers (from PlotState.renderChrome()) to GPU.
 * Skips text layers (handled separately by _applyTextLayers).
 */
function _applyChrome(gpu, chrome) {
  const TEXT_LAYERS = ['strip_labels_top', 'strip_labels_left', 'axis_labels'];

  for (const [category, elements] of Object.entries(chrome)) {
    if (!elements || elements.length === 0) continue;
    if (TEXT_LAYERS.includes(category)) continue; // Skip text layers

    const rects = elements.map(elem => ({
      x: elem.x,
      y: elem.y,
      w: elem.width,
      h: elem.height,
      color: _parseColor(elem.color || elem.fill),
    }));

    gpu.setLayer(category, rects);
  }
}

/**
 * Apply text layers to HTML div overlay (Layer 3).
 * Text is rendered via DOM, not GPU.
 */
function _applyTextLayers(containerId, chrome) {
  const TEXT_LAYERS = ['strip_labels_top', 'strip_labels_left', 'axis_labels'];

  // Find or create text layer div
  let textLayer = document.getElementById(`${containerId}-text`);
  if (!textLayer) {
    const container = document.getElementById(containerId);
    if (!container) return;

    textLayer = document.createElement('div');
    textLayer.id = `${containerId}-text`;
    textLayer.style.position = 'absolute';
    textLayer.style.top = '0';
    textLayer.style.left = '0';
    textLayer.style.width = '100%';
    textLayer.style.height = '100%';
    textLayer.style.pointerEvents = 'none'; // Don't block interactions
    textLayer.style.zIndex = '3'; // Above SVG chrome (z-index 2)
    container.appendChild(textLayer);
  }

  // Clear previous text
  textLayer.innerHTML = '';

  // Render each text layer
  for (const category of TEXT_LAYERS) {
    const elements = chrome[category];
    if (!elements || elements.length === 0) continue;

    for (const elem of elements) {
      const span = document.createElement('span');
      span.textContent = elem.text;
      span.style.position = 'absolute';
      span.style.left = `${elem.x}px`;
      span.style.top = `${elem.y}px`;
      span.style.fontSize = `${elem.fontSize || 12}px`;
      span.style.fontWeight = elem.fontWeight || '400';
      span.style.color = elem.color || '#374151';
      span.style.fontFamily = 'sans-serif';
      span.style.whiteSpace = 'nowrap';

      // Text alignment
      let transforms = [];
      if (elem.align === 'center') {
        transforms.push('translateX(-50%)');
      } else if (elem.align === 'right') {
        transforms.push('translateX(-100%)');
      }

      // Vertical centering for strip labels
      if (category.includes('strip_labels')) {
        transforms.push('translateY(-50%)');
      }

      if (transforms.length > 0) {
        span.style.transform = transforms.join(' ');
      }

      textLayer.appendChild(span);
    }
  }
}

// ─── MockStreamingRenderer ────────────────────────────────────────────────

/**
 * Mock WASM renderer for Phase 1 testing.
 * Generates synthetic faceted data with diagonal patterns.
 */
class MockStreamingRenderer {
  constructor(totalPoints, chunkSize, nCols, nRows) {
    this.totalPoints = totalPoints;
    this.chunkSize = chunkSize;
    this.currentOffset = 0;
    this.cancelled = false;
    this.nCols = nCols;
    this.nRows = nRows;

    this.xMin = 0;
    this.xMax = 100;
    this.yMin = 0;
    this.yMax = 100;

    this.quantizedData = this._generateQuantizedData(totalPoints);
  }

  _generateQuantizedData(count) {
    const data = [];
    const totalFacets = this.nCols * this.nRows;
    const pointsPerFacet = Math.max(1, Math.floor(count / totalFacets));

    for (let i = 0; i < count; i++) {
      const facetIndex = Math.floor(i / pointsPerFacet) % totalFacets;
      const ci = facetIndex % this.nCols;
      const ri = Math.floor(facetIndex / this.nCols);

      const facetLocalIndex = i % pointsPerFacet;
      const progress = facetLocalIndex / pointsPerFacet;

      const baseX = this.xMin + progress * (this.xMax - this.xMin);
      const baseY = this.yMin + progress * (this.yMax - this.yMin);
      const noise = (Math.random() - 0.5) * 10;

      const quantX = Math.floor(((baseX + noise - this.xMin) / (this.xMax - this.xMin)) * 65535 - 32768);
      const quantY = Math.floor(((baseY + noise - this.yMin) / (this.yMax - this.yMin)) * 65535 - 32768);

      data.push({ qx: quantX, qy: quantY, ci, ri });
    }
    return data;
  }

  loadDataChunk() {
    if (this.cancelled) {
      return { done: true, loaded: 0, total: this.totalPoints, points: [] };
    }

    const remaining = this.totalPoints - this.currentOffset;
    const count = Math.min(this.chunkSize, remaining);
    const chunkStart = this.currentOffset;
    const chunkEnd = chunkStart + count;

    const dequantized = [];
    for (let i = chunkStart; i < chunkEnd; i++) {
      const q = this.quantizedData[i];
      const x = ((q.qx + 32768) / 65535) * (this.xMax - this.xMin) + this.xMin;
      const y = ((q.qy + 32768) / 65535) * (this.yMax - this.yMin) + this.yMin;
      dequantized.push({ x, y, ci: q.ci, ri: q.ri });
    }

    this.currentOffset += count;
    const done = this.currentOffset >= this.totalPoints;

    return {
      done,
      loaded: this.currentOffset,
      total: this.totalPoints,
      points: dequantized,
    };
  }

  cancel() {
    this.cancelled = true;
  }
}

// ─── Range Computation Helpers ────────────────────────────────────────────

/**
 * Compute overlap (intersection) of needed and loaded ranges.
 * Returns null if no overlap.
 */
function computeOverlap(needed, loaded) {
  if (!loaded) return null;

  const colStart = Math.max(needed.colStart, loaded.colStart);
  const colEnd = Math.min(needed.colEnd, loaded.colEnd);
  const rowStart = Math.max(needed.rowStart, loaded.rowStart);
  const rowEnd = Math.min(needed.rowEnd, loaded.rowEnd);

  // Check if there's actual overlap
  if (colEnd <= colStart || rowEnd <= rowStart) {
    return null;
  }

  return { colStart, colEnd, rowStart, rowEnd };
}

/**
 * Compute NEW rectangles to load (facets in needed but not in loaded).
 * Returns array of 0-4 rectangles (could be empty if needed ⊆ loaded).
 */
function computeNewRectangles(needed, loaded) {
  if (!loaded || loaded.colEnd === 0) {
    // No previous data - load entire needed range
    return [needed];
  }

  const newRects = [];

  // Right extension (new columns on right edge)
  if (needed.colEnd > loaded.colEnd) {
    newRects.push({
      colStart: Math.max(loaded.colEnd, needed.colStart),
      colEnd: needed.colEnd,
      rowStart: needed.rowStart,
      rowEnd: needed.rowEnd,
    });
  }

  // Left extension (new columns on left edge)
  if (needed.colStart < loaded.colStart) {
    newRects.push({
      colStart: needed.colStart,
      colEnd: Math.min(loaded.colStart, needed.colEnd),
      rowStart: needed.rowStart,
      rowEnd: needed.rowEnd,
    });
  }

  // Bottom extension (new rows on bottom, only in column overlap)
  if (needed.rowEnd > loaded.rowEnd) {
    const overlapColStart = Math.max(needed.colStart, loaded.colStart);
    const overlapColEnd = Math.min(needed.colEnd, loaded.colEnd);
    if (overlapColEnd > overlapColStart) {
      newRects.push({
        colStart: overlapColStart,
        colEnd: overlapColEnd,
        rowStart: Math.max(loaded.rowEnd, needed.rowStart),
        rowEnd: needed.rowEnd,
      });
    }
  }

  // Top extension (new rows on top, only in column overlap)
  if (needed.rowStart < loaded.rowStart) {
    const overlapColStart = Math.max(needed.colStart, loaded.colStart);
    const overlapColEnd = Math.min(needed.colEnd, loaded.colEnd);
    if (overlapColEnd > overlapColStart) {
      newRects.push({
        colStart: overlapColStart,
        colEnd: overlapColEnd,
        rowStart: needed.rowStart,
        rowEnd: Math.min(loaded.rowStart, needed.rowEnd),
      });
    }
  }

  return newRects;
}

/**
 * Filter points to keep only those within the specified range.
 */
function filterPointsByRange(points, range) {
  if (!range) return [];
  return points.filter(p =>
    p.ci >= range.colStart && p.ci < range.colEnd &&
    p.ri >= range.rowStart && p.ri < range.rowEnd
  );
}

/**
 * Request data check (debounced to avoid checking on every scroll tick).
 * Moved out of setViewport() - data loading is now independent and async.
 */
function _requestDataCheck(containerId) {
  const instance = ggrsV3._gpuInstances.get(containerId);
  if (!instance) return;

  // Debounce: clear existing timeout, set new one
  if (instance._dataCheckTimeout) {
    clearTimeout(instance._dataCheckTimeout);
  }

  instance._dataCheckTimeout = setTimeout(() => {
    // Skip if previous load still in progress (prevents UI hitching during rapid scroll)
    if (instance._loadInProgress) {
      console.log('[bootstrap_v3] Skipping data check - load in progress');
      return;
    }

    // Call checkAndLoadNewFacets (which triggers onLoadFacets callback)
    instance.plotState.checkAndLoadNewFacets();
  }, 150); // 150ms debounce - increased to reduce hitching during scroll
}

/**
 * Start continuous render loop for smooth scrolling.
 *
 * Simplified architecture:
 * - Scroll events just update viewport.row/col (instant, no work)
 * - This loop runs at 60fps, reads viewport state, animates GPU offset
 * - Chrome rebuilds only when data chunks arrive (not on every scroll)
 *
 * Benefits:
 * - Decouples scroll events from rendering
 * - Smooth 60fps animation independent of event frequency
 * - Rapid scrolling doesn't block (just updates numbers)
 */
function _startContinuousRenderLoop(containerId) {
  const instance = ggrsV3._gpuInstances.get(containerId);
  if (!instance) return;

  const plotState = instance.plotState;
  const gpu = instance.gpu;

  // Initialize animation state
  if (!instance._animation) {
    instance._animation = {
      isAnimating: false,
      startTime: 0,
      duration: 200, // ms
      startCol: 0,
      startRow: 0,
      targetCol: 0,
      targetRow: 0,
      animationId: null,
    };
  }

  const anim = instance._animation;

  const renderLoop = () => {
    const vp = plotState.viewport;

    // Check if viewport target changed (from InteractionManager)
    const targetChanged =
      Math.abs(vp.col - anim.targetCol) > 0.001 ||
      Math.abs(vp.row - anim.targetRow) > 0.001;

    // IMPROVED: Allow scroll to interrupt current animation (responsive continuous scrolling)
    // To revert to old behavior (drop second scroll), add back: && !anim.isAnimating
    if (targetChanged) {
      // New target - start/restart animation from CURRENT position (not previous target)
      // This allows smooth interruption - each scroll retargets from where we are now
      anim.startCol = anim.isAnimating ? plotState.viewport.col : (anim.targetCol || vp.col);
      anim.startRow = anim.isAnimating ? plotState.viewport.row : (anim.targetRow || vp.row);
      anim.targetCol = vp.col;
      anim.targetRow = vp.row;
      anim.startTime = performance.now();
      anim.isAnimating = true;

      // Trigger async data check (debounced)
      _requestDataCheck(containerId);
    }

    // Interpolate viewport if animating
    if (anim.isAnimating) {
      const elapsed = performance.now() - anim.startTime;
      const progress = Math.min(elapsed / anim.duration, 1.0);
      const eased = 1 - Math.pow(1 - progress, 3); // Ease-out cubic

      // Interpolate viewport position
      const interpolatedCol = anim.startCol + (anim.targetCol - anim.startCol) * eased;
      const interpolatedRow = anim.startRow + (anim.targetRow - anim.startRow) * eased;

      // Update PlotState viewport with interpolated values
      plotState.viewport.col = interpolatedCol;
      plotState.viewport.row = interpolatedRow;

      if (progress >= 1.0) {
        // Animation complete - snap to final values
        plotState.viewport.col = anim.targetCol;
        plotState.viewport.row = anim.targetRow;
        anim.isAnimating = false;
      }
    }

    // Recompute layout based on current (interpolated) viewport
    plotState._recomputeLayout();
    const layout = plotState.layout;

    // Rebuild chrome every frame during animation (positions calculated relative to interpolated viewport)
    // Outside animation, chrome only rebuilds when data arrives
    if (anim.isAnimating) {
      const chrome = plotState.renderChrome();
      _applyChrome(gpu, chrome);
      _applyTextLayers(containerId, chrome);
    }

    // Sync layout state to GPU
    const layoutState = plotState.buildLayoutState();
    gpu.syncLayoutState(JSON.stringify(layoutState));

    // Continue loop
    anim.animationId = requestAnimationFrame(renderLoop);
  };

  // Start the loop
  anim.animationId = requestAnimationFrame(renderLoop);
  console.log(`[bootstrap_v3] Started continuous render loop for ${containerId}`);
}

// ─── Main API ─────────────────────────────────────────────────────────────

const ggrsV3 = {
  ensureWasmInitialized,
  createRenderer,
  _gpuInstances: new Map(),

  /**
   * Ensure GPU is initialized for a container.
   * Creates GPU, PlotState, and InteractionManager on first call.
   * Updates canvas/layout dimensions on subsequent calls (e.g., resize).
   */
  async ggrsV3EnsureGpu(containerId, width, height, renderer) {
    console.log(`[bootstrap_v3] ensureGpu(${containerId}, ${width}x${height})`);

    // If already initialized, just update dimensions
    if (ggrsV3._gpuInstances.has(containerId)) {
      console.log(`[bootstrap_v3] GPU already initialized, updating dimensions`);
      const instance = ggrsV3._gpuInstances.get(containerId);
      instance.gpu.resize(width, height);
      instance.plotState.resize(width, height);
      return;
    }

    // Find or create canvas
    let canvas = document.getElementById(`${containerId}-canvas`);
    if (!canvas) {
      const container = document.getElementById(containerId);
      if (!container) {
        throw new Error(`Container ${containerId} not found`);
      }
      canvas = document.createElement('canvas');
      canvas.id = `${containerId}-canvas`;
      canvas.style.position = 'absolute';
      canvas.style.top = '0';
      canvas.style.left = '0';
      canvas.style.width = '100%';
      canvas.style.height = '100%';
      canvas.style.display = 'block';
      canvas.style.zIndex = '1';
      container.appendChild(canvas);
    }

    // Create GPU
    const gpu = new GgrsGpuV3();
    await gpu.init(canvas);
    gpu.resize(width, height);

    // Create interaction div overlay
    let interactionDiv = document.getElementById(`${containerId}-interaction`);
    if (!interactionDiv) {
      interactionDiv = document.createElement('div');
      interactionDiv.id = `${containerId}-interaction`;
      interactionDiv.style.position = 'absolute';
      interactionDiv.style.top = '0';
      interactionDiv.style.left = '0';
      interactionDiv.style.width = '100%';
      interactionDiv.style.height = '100%';
      interactionDiv.style.pointerEvents = 'all';
      interactionDiv.style.zIndex = '10';
      canvas.parentElement.appendChild(interactionDiv);
    }

    // Create PlotOrchestrator (state machine) and set proper state sequence
    const orchestrator = new PlotOrchestrator(containerId);

    // By this point, WASM is initialized (ensured in ensureWasmInitialized)
    if (wasmInitialized) {
      orchestrator.setState('WASM_READY');
    }

    // Renderer was created and passed in
    if (renderer) {
      orchestrator.setState('RENDERER_READY', { renderer });
    }

    // GPU just created successfully
    orchestrator.setState('GPU_READY', { width, height });

    // Create PlotState (centralized state)
    const plotState = new PlotState({
      canvasWidth: width,
      canvasHeight: height,
      cellSpacing: 10,
      initialVisibleCols: 3.0,
      initialVisibleRows: 3.0,
    });

    // Background facet loading callback (triggered when viewport changes - scroll/zoom)
    // Implements sliding window: DISCARD out-of-view, KEEP overlap, LOAD new facets
    plotState.onLoadFacets = (neededRange, loadId) => {
      console.log(`[bootstrap_v3] ========== onLoadFacets CALLBACK TRIGGERED (load #${loadId}) ==========`);
      const loadedRange = plotState.loadedFacets;

      console.log(`[bootstrap_v3] Needed: cols [${neededRange.colStart}, ${neededRange.colEnd}), rows [${neededRange.rowStart}, ${neededRange.rowEnd})`);
      console.log(`[bootstrap_v3] Loaded: cols [${loadedRange.colStart}, ${loadedRange.colEnd}), rows [${loadedRange.rowStart}, ${loadedRange.rowEnd})`);
      console.log(`[bootstrap_v3] Current GPU points: ${(gpu._allPoints || []).length}`);

      // 1. Compute OVERLAP (intersection) - facets to KEEP
      // Don't filter immediately - defer to appendDataPoints to avoid blocking
      const overlap = computeOverlap(neededRange, loadedRange);
      console.log(`[bootstrap_v3] Overlap: ${overlap ? `cols [${overlap.colStart}, ${overlap.colEnd}), rows [${overlap.rowStart}, ${overlap.rowEnd})` : 'NONE'}`);

      // Store overlap in history snapshot for filtering later
      const snapshot = plotState.getLoadSnapshot(loadId);
      if (snapshot) {
        snapshot.overlap = overlap;
        console.log(`[bootstrap_v3] Stored overlap in snapshot #${loadId} (will filter during append)`);
      }

      // 2. Compute NEW rectangles to LOAD
      const newRects = computeNewRectangles(neededRange, loadedRange);
      console.log(`[bootstrap_v3] New rectangles to load: ${newRects.length}`);

      if (newRects.length === 0) {
        console.log(`[bootstrap_v3] No new facets to load (needed ⊆ loaded) - filtering existing points`);
        // Filter existing points based on overlap (non-blocking)
        requestAnimationFrame(() => {
          const filtered = overlap ? filterPointsByRange(gpu._allPoints || [], overlap) : [];
          console.log(`[bootstrap_v3] Filtered ${(gpu._allPoints || []).length} → ${filtered.length} points`);
          gpu.setDataPoints(filtered);
          plotState.markFacetsLoaded(neededRange.colStart, neededRange.colEnd, neededRange.rowStart, neededRange.rowEnd);
          plotState.removeLoadSnapshot(loadId);
        });
        return;
      }

      newRects.forEach((rect, i) => {
        console.log(`[bootstrap_v3]   Rect ${i + 1}: cols [${rect.colStart}, ${rect.colEnd}), rows [${rect.rowStart}, ${rect.rowEnd})`);
      });

      // 4. Post message to Dart to load new rectangles
      console.log(`[bootstrap_v3] Posting 'load-facets' message to Dart (load #${loadId})...`);
      window.parent.postMessage({
        type: 'load-facets',
        source: { appId: 'step-viewer', instanceId: containerId },
        target: 'step-viewer',
        payload: {
          containerId,
          newRectangles: newRects,
          neededRange: neededRange,  // For Dart to update loadedFacets after loading
          loadId: loadId,            // History ID for correct placement
        },
      }, '*');
      console.log(`[bootstrap_v3] Message posted!`);
    };

    // Chrome rebuild callback (used by InteractionManager)
    const onChromeRebuild = () => {
      const chrome = plotState.renderChrome();
      _applyChrome(gpu, chrome);           // GPU: rects (strips, axes, ticks)
      _applyTextLayers(containerId, chrome); // DOM: text (labels)
    };

    // Create InteractionManager (viewport-driven, no WASM calls)
    const interactionManager = new InteractionManager(
      containerId, gpu, interactionDiv, plotState, onChromeRebuild,
    );

    ggrsV3._gpuInstances.set(containerId, {
      gpu, renderer, interactionManager, plotState, orchestrator,
    });

    // Start continuous render loop (60fps) - decoupled from scroll events
    // Handles smooth scrolling via GPU offset animation
    _startContinuousRenderLoop(containerId);

    console.log(`[bootstrap_v3] Created GgrsGpuV3 + PlotState + InteractionManager + continuous render loop for ${containerId}`);
  },

  /**
   * Get GPU instance for a container
   */
  ggrsV3GetGpu(containerId) {
    const instance = ggrsV3._gpuInstances.get(containerId);
    return instance ? instance.gpu : null;
  },

  /**
   * Set plot metadata from WASM initPlotStream result (Phase 2).
   * Populates PlotState with grid dimensions, axis ranges, facet labels, chrome styles.
   */
  ggrsV3SetPlotMetadata(containerId, metadataJson) {
    console.log(`[bootstrap_v3] setPlotMetadata(${containerId})`);
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance) {
      throw new Error(`No GPU instance for ${containerId}`);
    }
    const metadata = typeof metadataJson === 'string'
      ? JSON.parse(metadataJson)
      : metadataJson;
    instance.plotState.setMetadata(metadata);
    instance.orchestrator.setState('METADATA_READY', { metadata });
    console.log(`[bootstrap_v3] Plot metadata set:`, metadata);
  },

  /**
   * Configure viewport with grid dimensions and axis ranges.
   * Call after initPlotStream returns metadata (Phase 2) or with mock values (Phase 1).
   */
  ggrsV3SetViewportConfig(containerId, config) {
    console.log(`[bootstrap_v3] setViewportConfig(${containerId})`, config);
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance) {
      throw new Error(`No GPU instance for ${containerId}`);
    }
    instance.plotState.setGridConfig(config);
  },

  /**
   * Render chrome from PlotState and apply to GPU (rects) and DOM (text).
   */
  ggrsV3RenderChrome(containerId, chromeJsonOrUndefined) {
    console.log(`[bootstrap_v3] renderChrome(${containerId})`);
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance) {
      throw new Error(`No GPU instance for ${containerId}`);
    }

    let chrome;
    if (chromeJsonOrUndefined) {
      // External chrome data (from test harness or WASM)
      chrome = typeof chromeJsonOrUndefined === 'string'
        ? JSON.parse(chromeJsonOrUndefined)
        : chromeJsonOrUndefined;
    } else {
      // Generate from PlotState
      chrome = instance.plotState.renderChrome();
    }

    _applyChrome(instance.gpu, chrome);           // GPU: rects
    _applyTextLayers(containerId, chrome);         // DOM: text
    instance.orchestrator.setState('CHROME_READY');
    console.log(`[bootstrap_v3] Chrome rendered: ${Object.keys(chrome).length} categories`);
  },

  // ── COMMENTED OUT: Manual sync layout (replaced by continuous render loop) ──
  //
  // Old approach: called from interaction handlers on every scroll/zoom event
  // New approach: continuous 60fps render loop handles all GPU sync + animation
  //
  // Benefits of continuous loop:
  // - Decouples scroll events from rendering (scroll just updates numbers)
  // - Guaranteed smooth 60fps (not event-dependent)
  // - No blocking work in scroll handlers
  // - Chrome only rebuilds when data arrives (not on every scroll)
  //
  // /**
  //  * Sync layout state from PlotState to GPU with smooth scrolling.
  //  */
  // ggrsV3SyncLayout(containerId) {
  //   ...
  // },

  /**
   * Set data points directly on GPU.
   */
  ggrsV3SetDataPoints(containerId, points) {
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance) {
      throw new Error(`No GPU instance for ${containerId}`);
    }
    instance.gpu.setDataPoints(points);
  },

  /**
   * Stream mock data from WASM MockStreamGenerator (Phase 1 testing).
   *
   * @param {string} containerId - Container ID
   * @param {Object} opts - Options
   * @param {number} opts.chunkSize - Rows per chunk (default 5000)
   * @param {Object} opts.facet_filter - Optional DataFilter for viewport-aware loading
   */
  async ggrsV3StreamMockData(containerId, opts = {}) {
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance || !instance.renderer) {
      throw new Error(`No GPU/renderer instance for ${containerId}`);
    }

    const chunkSize = opts.chunkSize || 5000;
    const facet_filter = opts.facet_filter || null;
    const filterJson = facet_filter ? JSON.stringify(facet_filter) : null;

    console.log(`[bootstrap_v3] Streaming mock data, chunkSize=${chunkSize}, filter=${filterJson ? 'yes' : 'none'}`);

    // Transition to DATA_STREAMING state
    instance.orchestrator.setState('DATA_STREAMING');

    const allPoints = [];
    let pendingPoints = []; // Queue for render loop
    let done = false;
    let chunkCount = 0;
    let lastRenderTime = 0;
    const RENDER_INTERVAL_MS = 16; // ~60fps

    // Async render loop - runs independently from fetch loop
    const renderPending = () => {
      console.log(`[bootstrap_v3] renderPending() called: pendingPoints=${pendingPoints.length}, timeSinceLastRender=${performance.now() - lastRenderTime}ms`);

      if (pendingPoints.length === 0) {
        console.log(`[bootstrap_v3]   → Skipping (no pending points)`);
        return;
      }

      const now = performance.now();
      if (now - lastRenderTime < RENDER_INTERVAL_MS) {
        console.log(`[bootstrap_v3]   → Skipping (throttled, need ${RENDER_INTERVAL_MS}ms interval)`);
        return;
      }

      const newPointCount = pendingPoints.length;
      allPoints.push(...pendingPoints);
      console.log(`[bootstrap_v3]   → Rendering: ${allPoints.length} total points (+${newPointCount} new)`);

      instance.gpu.setDataPoints(allPoints);
      lastRenderTime = now;

      console.log(`[bootstrap_v3] ✓ Rendered ${allPoints.length} total points`);
      pendingPoints = [];
    };

    // Fetch loop - grabs chunks as fast as WASM can produce them
    while (!done) {
      const resultJson = await instance.renderer.loadDataChunk(chunkSize, filterJson);
      const result = JSON.parse(resultJson);

      if (result.error) {
        throw new Error(`Mock data chunk error: ${result.error}`);
      }

      // Diagnostic logging
      console.log(`[bootstrap_v3] Chunk result:`, {
        hasPoints: !!result.points,
        pointsLength: result.points?.length || 0,
        done: result.done,
        loaded: result.loaded,
        total: result.total,
      });

      if (result.points && result.points.length > 0) {
        console.log(`[bootstrap_v3] Processing ${result.points.length} points from chunk ${chunkCount}`);

        const gpuPoints = result.points.map(p => ({
          x: p.x,
          y: p.y,
          ci: p.ci,
          ri: p.ri,
          color_packed: 0x0000FFFF, // Blue
          size: 3.0,
        }));

        console.log(`[bootstrap_v3] Mapped to ${gpuPoints.length} GPU points`);

        // Add to pending queue (don't wait for render)
        pendingPoints.push(...gpuPoints);
        console.log(`[bootstrap_v3] Pending queue now has ${pendingPoints.length} points`);

        // Log first chunk sample
        if (chunkCount === 0 && gpuPoints.length > 0) {
          console.log(`[bootstrap_v3] SAMPLE POINTS (first 5):`, gpuPoints.slice(0, 5));
          console.log(`[bootstrap_v3]   Point 0: x=${gpuPoints[0].x.toFixed(2)}, y=${gpuPoints[0].y.toFixed(2)}, ci=${gpuPoints[0].ci}, ri=${gpuPoints[0].ri}`);
        }
        chunkCount++;

        // Render if enough points accumulated (don't block fetch)
        console.log(`[bootstrap_v3] Calling renderPending()...`);
        renderPending();
      } else {
        console.warn(`[bootstrap_v3] ⚠ Chunk ${chunkCount} has NO POINTS! (points=${result.points?.length || 0})`);
      }

      done = result.done;
      console.log(`[bootstrap_v3] Fetched chunk ${chunkCount}: ${result.loaded}/${result.total} rows`);

      // Yield to browser (but don't wait for render)
      await new Promise(resolve => setTimeout(resolve, 0));
    }

    // Final render for any remaining points
    if (pendingPoints.length > 0) {
      allPoints.push(...pendingPoints);
      instance.gpu.setDataPoints(allPoints);
      console.log(`[bootstrap_v3] Final render: ${allPoints.length} total points`);
    }

    // Mark loaded facets in PlotState (don't overwrite if viewport changed during load)
    if (facet_filter && facet_filter.facet) {
      const fr = facet_filter.facet;
      if (fr.col_range && fr.row_range) {
        instance.plotState.markFacetsLoaded(
          fr.col_range[0],
          fr.col_range[1],
          fr.row_range[0],
          fr.row_range[1],
          false  // Don't overwrite if viewport has already changed
        );
      }
    }

    // Transition to DATA_READY and READY states
    instance.orchestrator.setState('DATA_READY', { pointCount: allPoints.length });
    instance.orchestrator.setState('READY');

    console.log(`[bootstrap_v3] Mock streaming complete: ${allPoints.length} points in ${chunkCount} chunks`);
    return allPoints.length;
  },

  /**
   * Stream real data from WASM loadDataChunk.
   * Phase 2: after initPlotStream, call this to load actual Tercen data.
   *
   * @param {string} containerId - Container ID
   * @param {number} chunkSize - Rows per chunk (default 15000)
   * @param {Object} filter - Optional DataFilter: { facet: { col_range, row_range }, spatial: { x_column, x_min, x_max, y_column, y_min, y_max } }
   */
  async ggrsV3StreamData(containerId, chunkSize = 15000, filter = null) {
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance || !instance.renderer) {
      throw new Error(`No GPU/renderer instance for ${containerId}`);
    }

    const filterJson = filter ? JSON.stringify(filter) : null;
    console.log(`[bootstrap_v3] Streaming real data, chunkSize=${chunkSize}, filter=${filterJson ? 'yes' : 'none'}`);

    const allPoints = [];
    let done = false;

    while (!done) {
      const resultJson = await instance.renderer.loadDataChunk(chunkSize, filterJson);
      const result = JSON.parse(resultJson);

      if (result.error) {
        throw new Error(`Data chunk error: ${result.error}`);
      }

      if (result.points) {
        const gpuPoints = result.points.map(p => ({
          x: p.x,
          y: p.y,
          ci: p.ci,
          ri: p.ri,
          color_packed: _packColorU32(0.2, 0.4, 0.8, 0.8),
          size: 3.0,
        }));
        allPoints.push(...gpuPoints);
        instance.gpu.setDataPoints(allPoints);
      }

      done = result.done;
      console.log(`[bootstrap_v3] Loaded ${result.loaded}/${result.total} rows`);

      // Yield for progressive paint
      await new Promise(resolve => setTimeout(resolve, 0));
    }

    console.log(`[bootstrap_v3] Streaming complete: ${allPoints.length} points`);
    return allPoints.length;
  },

  /**
   * Append new data points to GPU (for incremental facet loading).
   * Called after background streaming completes for new facet rectangles.
   * Merges new points with kept overlap points.
   *
   * @param {string} containerId - Container ID
   * @param {Array} points - Array of {x, y, ci, ri} points from new rectangles
   * @param {Object} neededRange - Full needed facet range {colStart, colEnd, rowStart, rowEnd}
   */
  ggrsV3AppendDataPoints(containerId, points, neededRange, loadId) {
    console.log(`[bootstrap_v3] ========== ggrsV3AppendDataPoints CALLED (load #${loadId}) ==========`);
    console.log(`[bootstrap_v3] containerId: ${containerId}`);
    console.log(`[bootstrap_v3] points.length: ${points.length}`);
    console.log(`[bootstrap_v3] neededRange: cols [${neededRange.colStart}, ${neededRange.colEnd}), rows [${neededRange.rowStart}, ${neededRange.rowEnd})`);

    const instance = ggrsV3._gpuInstances.get(containerId);
    if (!instance) {
      console.error(`[bootstrap_v3] ⚠️ No GPU instance for ${containerId}`);
      throw new Error(`No GPU instance for ${containerId}`);
    }

    // Set load in progress flag (prevents concurrent loads from hitching)
    instance._loadInProgress = true;

    // Retrieve historical snapshot for this load
    const snapshot = instance.plotState.getLoadSnapshot(loadId);
    if (!snapshot) {
      console.warn(`[bootstrap_v3] ⚠️ No snapshot found for load #${loadId}, using current state`);
    } else {
      console.log(`[bootstrap_v3] Using historical snapshot #${loadId}: viewport row=${snapshot.viewport.row.toFixed(2)}, cols=${snapshot.viewport.visibleCols.toFixed(1)}`);
    }

    const currentPoints = instance.gpu._allPoints || [];
    console.log(`[bootstrap_v3] Current GPU _allPoints: ${currentPoints.length}`);

    // Filter existing points based on historical overlap (deferred from onLoadFacets)
    const overlap = snapshot ? snapshot.overlap : null;
    const keptPoints = overlap ? filterPointsByRange(currentPoints, overlap) : [];
    console.log(`[bootstrap_v3] Filtering existing points: ${currentPoints.length} → ${keptPoints.length} (using historical overlap)`);

    // Convert new points to GPU format
    const gpuPoints = points.map(p => ({
      x: p.x,
      y: p.y,
      ci: p.ci,
      ri: p.ri,
      color_packed: 0x0000FFFF, // Blue
      size: 3.0,
    }));

    console.log(`[bootstrap_v3] Converted ${gpuPoints.length} new points to GPU format`);

    // Merge kept overlap + new points
    const mergedPoints = [...keptPoints, ...gpuPoints];
    console.log(`[bootstrap_v3] Merging: ${keptPoints.length} kept + ${gpuPoints.length} new = ${mergedPoints.length} total`);

    // Set merged points (replaces all GPU points)
    instance.gpu.setDataPoints(mergedPoints);

    console.log(`[bootstrap_v3] After append, GPU _allPoints: ${instance.gpu._allPoints.length}`);

    // Update loadedFacets via PlotState (single source of truth)
    if (neededRange) {
      console.log(`[bootstrap_v3] Calling plotState.markFacetsLoaded...`);
      instance.plotState.markFacetsLoaded(
        neededRange.colStart,
        neededRange.colEnd,
        neededRange.rowStart,
        neededRange.rowEnd
      );
    }

    // Remove historical snapshot now that data is placed
    instance.plotState.removeLoadSnapshot(loadId);

    // Rebuild chrome now that new data has arrived
    // (ONLY rebuild on data arrival, not on scroll events - animation handles scroll chrome updates)
    console.log(`[bootstrap_v3] Rebuilding chrome after data chunk processed...`);
    const chrome = instance.plotState.renderChrome();
    _applyChrome(instance.gpu, chrome);           // GPU: rects (strips, axes, ticks)
    _applyTextLayers(containerId, chrome);        // DOM: text (labels)
    console.log(`[bootstrap_v3] Chrome rebuilt`);

    // Clear load in progress flag (allows next load to proceed)
    instance._loadInProgress = false;

    console.log(`[bootstrap_v3] ========== ggrsV3AppendDataPoints COMPLETE ==========`);
  },

  /**
   * Cleanup GPU and interaction manager.
   */
  ggrsV3Cleanup(containerId) {
    console.log(`[bootstrap_v3] cleanup(${containerId})`);
    const instance = ggrsV3._gpuInstances.get(containerId);
    if (instance) {
      // Stop continuous render loop
      if (instance._animation && instance._animation.animationId) {
        cancelAnimationFrame(instance._animation.animationId);
      }
      if (instance.gpu) instance.gpu.destroy();
      if (instance.interactionManager) instance.interactionManager.destroy();
      if (instance.plotState) instance.plotState.destroy();
    }
    ggrsV3._gpuInstances.delete(containerId);
  },
};

// Export to global scope
window.ggrsV3 = ggrsV3;

console.log('[bootstrap_v3] V3 bootstrap loaded (PlotState-driven rendering)');
