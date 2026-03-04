// PlotState - Single source of truth for all plot metadata and viewport state
//
// Centralized state object that holds:
// - Metadata from WASM (grid dimensions, axis ranges, facet labels, chrome styles)
// - Viewport state (user zoom/scroll position)
// - Derived layout (cell dimensions, facet pixel positions)
// - Spatial index (for point queries - Phase 2)
//
// Populated once from WASM initPlotStream, then updated synchronously by JS interactions.

export class PlotState {
  constructor(config = {}) {
    // Canvas dimensions
    this.canvasWidth = config.canvasWidth || 800;
    this.canvasHeight = config.canvasHeight || 600;
    this.cellSpacing = config.cellSpacing || 10;

    // Metadata from WASM (populated via setMetadata)
    this.metadata = {
      grid: {
        totalCols: 0,
        totalRows: 0,
      },
      axes: {
        xMin: 0,
        xMax: 100,
        yMin: 0,
        yMax: 100,
      },
      facets: {
        colLabels: [],
        rowLabels: [],
      },
      chrome: {
        panelFill: '#FFFFFF',        // Plot area background
        borderColor: '#D1D5DB',      // Panel borders
        gridLineColor: '#E5E7EB',    // Grid between panels
        axisLineColor: '#374151',    // Axis lines (darker)
        tickMarkColor: '#6B7280',    // Tick marks
        textColor: '#374151',        // All text (labels, ticks)
        stripFill: '#F3F4F6',        // Facet strip backgrounds
      },
      data: {
        nRows: 0,
      },
      dataInsets: {
        left: 50,    // From WASM layout - space for Y axis chrome
        top: 0,
        right: 10,   // Small padding
        bottom: 50,  // From WASM layout - space for X axis chrome
      },
    };

    // Viewport state (user interactions)
    this.viewport = {
      col: 0.0,
      row: 0.0,
      visibleCols: config.initialVisibleCols || 3.0,
      visibleRows: config.initialVisibleRows || 3.0,
    };

    // Derived layout (computed from metadata + viewport)
    this.layout = {
      cellWidth: 0,
      cellHeight: 0,
    };

    // Spatial index for point queries (built after data loads - Phase 2)
    this.spatialIndex = null;

    // Facet loading state (for incremental viewport-aware loading)
    this.loadedFacets = {
      colStart: 0,
      colEnd: 0,
      rowStart: 0,
      rowEnd: 0,
    };

    // ── ANIMATION STATE (COMMENTED OUT - moved to GPU) ──
    // JavaScript-side animation was causing race conditions:
    // - Rapid scroll events would update _animationStartTime while old frame callbacks were queued
    // - This caused negative progress values and viewport corruption
    // - Chrome was rebuilding 60fps during animation (wasteful)
    //
    // New approach: viewport updates immediately, GPU handles smooth visual transition
    // via scroll_offset uniforms (like CSS transforms). See ggrs_gpu_v3.js.
    //
    // this._animationId = null;
    // this._animationStartTime = 0;
    // this._animationDuration = 200; // ms
    // this._animationStart = null;
    // this._animationTarget = null;
    // this._animationGeneration = 0;

    // Callback for when new facets need loading
    this.onLoadFacets = null;

    // History of viewport states for in-flight loads
    // Each entry: { id, viewport, layout, neededRange, timestamp }
    this._loadHistory = [];
    this._nextLoadId = 1;

    this._recomputeLayout();
  }

  // ── Canvas Management ──────────────────────────────────────────────────

  /**
   * Update canvas dimensions (e.g., on window resize).
   * Preserves metadata and viewport state, only updates layout.
   */
  resize(width, height) {
    console.log(`[PlotState] resize(${width}, ${height})`);
    this.canvasWidth = width;
    this.canvasHeight = height;
    this._recomputeLayout();
  }

  // ── Metadata Management ────────────────────────────────────────────────

  /**
   * Set metadata from WASM initPlotStream result.
   * Called once after WASM returns metadata JSON.
   * Metadata is immutable once set (until new plot loaded).
   */
  setMetadata(metadata) {
    if (metadata.grid) {
      this.metadata.grid = { ...metadata.grid };
    }
    if (metadata.axes) {
      this.metadata.axes = { ...metadata.axes };
    }
    if (metadata.facets) {
      this.metadata.facets = { ...metadata.facets };
    }
    if (metadata.chrome) {
      this.metadata.chrome = { ...metadata.chrome };
    }
    if (metadata.data) {
      this.metadata.data = { ...metadata.data };
    }
    if (metadata.dataInsets) {
      this.metadata.dataInsets = { ...metadata.dataInsets };
    }

    this._recomputeLayout();
  }

  /**
   * Set grid configuration (Phase 1: mock data, hardcoded values)
   */
  setGridConfig(config) {
    console.log('[PlotState] setGridConfig called with:', config);

    if (config.totalCols !== undefined) {
      this.metadata.grid.totalCols = config.totalCols;
    }
    if (config.totalRows !== undefined) {
      this.metadata.grid.totalRows = config.totalRows;
    }
    if (config.xMin !== undefined) this.metadata.axes.xMin = config.xMin;
    if (config.xMax !== undefined) this.metadata.axes.xMax = config.xMax;
    if (config.yMin !== undefined) this.metadata.axes.yMin = config.yMin;
    if (config.yMax !== undefined) this.metadata.axes.yMax = config.yMax;

    console.log('[PlotState] After setGridConfig:');
    console.log('[PlotState]   grid:', this.metadata.grid);
    console.log('[PlotState]   axes:', this.metadata.axes);
    console.log('[PlotState]   viewport:', this.viewport);
    console.log('[PlotState]   layout:', this.layout);

    this._recomputeLayout();
  }

  // ── Viewport Management ────────────────────────────────────────────────

  /**
   * Set viewport position and zoom level.
   * Pure state update - just updates numbers, no side effects.
   * Layout computation happens in render loop (derived state).
   * Data loading check happens independently (debounced).
   */
  setViewport(col, row, visibleCols, visibleRows) {
    const { totalCols, totalRows } = this.metadata.grid;

    // Guard: ignore viewport updates until metadata is ready
    // Prevents "snap back to 0" from clamping against totalCols=0
    if (totalCols <= 0 || totalRows <= 0) {
      return;
    }

    // Clamp visible range
    this.viewport.visibleCols = Math.max(0.5, Math.min(visibleCols, totalCols));
    this.viewport.visibleRows = Math.max(0.5, Math.min(visibleRows, totalRows));

    // Clamp position
    const maxCol = Math.max(0, totalCols - this.viewport.visibleCols);
    const maxRow = Math.max(0, totalRows - this.viewport.visibleRows);
    this.viewport.col = Math.max(0, Math.min(col, maxCol));
    this.viewport.row = Math.max(0, Math.min(row, maxRow));

    // That's it! No _recomputeLayout(), no checkAndLoadNewFacets()
    // Layout computed in render loop, data check triggered separately
  }

  // ── COMMENTED OUT: JavaScript animation (replaced by GPU-side smooth scrolling) ──
  //
  // This animateTo() method had critical race condition bugs:
  // 1. Rapid scroll events would call animateTo() multiple times
  // 2. Each call updates _animationStartTime = performance.now()
  // 3. Old animation frame callbacks could fire with NEW timestamp values
  // 4. Result: negative progress values, viewport corruption to negative coordinates
  // 5. Also: chrome rebuilt 60fps during animation (12 rebuilds per 200ms scroll)
  //
  // GPU-side approach eliminates these issues:
  // - Viewport updates immediately (stable, no interpolation, no race conditions)
  // - GPU uniform scroll_offset_x/y compensates for visual jump
  // - Simple RAF loop smoothly interpolates offset from compensation → 0
  // - Chrome only rebuilds when facets actually change (integer boundary crossings)
  // - Shader adds offset to positions (like CSS transforms)
  //
  // /**
  //  * Animate viewport to target position/zoom with 200ms ease-out cubic.
  //  */
  // animateTo(targetCol, targetRow, targetVisCols, targetVisRows, onFrame, onComplete) {
  //   // Cancel existing animation
  //   if (this._animationId !== null) {
  //     cancelAnimationFrame(this._animationId);
  //   }
  //
  //   const { totalCols, totalRows } = this.metadata.grid;
  //
  //   // Clamp targets
  //   const clampedVisCols = Math.max(0.5, Math.min(targetVisCols, totalCols));
  //   const clampedVisRows = Math.max(0.5, Math.min(targetVisRows, totalRows));
  //   const maxCol = Math.max(0, totalCols - clampedVisCols);
  //   const maxRow = Math.max(0, totalRows - clampedVisRows);
  //   const clampedCol = Math.max(0, Math.min(targetCol, maxCol));
  //   const clampedRow = Math.max(0, Math.min(targetRow, maxRow));
  //
  //   this._animationStart = { ...this.viewport };
  //   this._animationTarget = {
  //     col: clampedCol,
  //     row: clampedRow,
  //     visibleCols: clampedVisCols,
  //     visibleRows: clampedVisRows,
  //   };
  //   this._animationStartTime = performance.now();
  //
  //   // Debug: catch negative viewport values
  //   if (this._animationStart.row < 0 || this._animationTarget.row < 0) {
  //     console.error(`[PlotState] CORRUPT ANIMATION STATE!`);
  //     console.error(`  _animationStart.row = ${this._animationStart.row}`);
  //     console.error(`  _animationTarget.row = ${this._animationTarget.row}`);
  //     console.error(`  targetRow (input) = ${targetRow}`);
  //     console.error(`  clampedRow (after clamp) = ${clampedRow}`);
  //     console.trace();
  //   }
  //
  //   const animate = (currentTime) => {
  //     const elapsed = currentTime - this._animationStartTime;
  //     const progress = Math.min(elapsed / this._animationDuration, 1.0);
  //
  //     // Ease-out cubic: 1 - (1 - t)^3
  //     const eased = 1 - Math.pow(1 - progress, 3);
  //
  //     this.viewport.col = this._animationStart.col +
  //       (this._animationTarget.col - this._animationStart.col) * eased;
  //     this.viewport.row = this._animationStart.row +
  //       (this._animationTarget.row - this._animationStart.row) * eased;
  //     this.viewport.visibleCols = this._animationStart.visibleCols +
  //       (this._animationTarget.visibleCols - this._animationStart.visibleCols) * eased;
  //     this.viewport.visibleRows = this._animationStart.visibleRows +
  //       (this._animationTarget.visibleRows - this._animationStart.visibleRows) * eased;
  //
  //     // Debug: catch negative viewport during animation
  //     if (this.viewport.row < 0) {
  //       console.error(`[PlotState] VIEWPORT ROW WENT NEGATIVE DURING ANIMATION!`);
  //       console.error(`  viewport.row = ${this.viewport.row}`);
  //       console.error(`  _animationStart.row = ${this._animationStart.row}`);
  //       console.error(`  _animationTarget.row = ${this._animationTarget.row}`);
  //       console.error(`  eased = ${eased}, progress = ${progress}`);
  //     }
  //
  //     this._recomputeLayout();
  //
  //     if (onFrame) onFrame();
  //
  //     if (progress < 1.0) {
  //       this._animationId = requestAnimationFrame(animate);
  //     } else {
  //       this._animationId = null;
  //
  //       // Check for new facets after animation completes
  //       this.checkAndLoadNewFacets();
  //
  //       if (onComplete) onComplete();
  //     }
  //   };
  //
  //   this._animationId = requestAnimationFrame(animate);
  // }
  //
  // /**
  //  * Cancel ongoing animation.
  //  */
  // cancelAnimation() {
  //   if (this._animationId !== null) {
  //     cancelAnimationFrame(this._animationId);
  //     this._animationId = null;
  //   }
  // }

  // ── Layout Computation ─────────────────────────────────────────────────

  /**
   * Recompute derived layout from metadata + viewport.
   * Called whenever viewport or metadata changes.
   */
  _recomputeLayout() {
    const { visibleCols, visibleRows } = this.viewport;
    const totalSpacingX = (visibleCols - 1) * this.cellSpacing;
    const totalSpacingY = (visibleRows - 1) * this.cellSpacing;

    // Reserve space for facet strips (headers)
    const STRIP_WIDTH = 60;
    const STRIP_HEIGHT = 30;
    const reservedWidth = STRIP_WIDTH + this.cellSpacing;   // 70px for left strip
    const reservedHeight = STRIP_HEIGHT + this.cellSpacing; // 40px for top strip

    // Compute cell dimensions from remaining space after strips
    const availableWidth = this.canvasWidth - reservedWidth;
    const availableHeight = this.canvasHeight - reservedHeight;

    this.layout.cellWidth = (availableWidth - totalSpacingX) / visibleCols;
    this.layout.cellHeight = (availableHeight - totalSpacingY) / visibleRows;

    // Removed 60fps logging (300 lines/sec at 60fps)
  }

  /**
   * Build full layout state object for GPU syncLayoutState().
   * Format matches test_streaming.html reference implementation.
   */
  buildLayoutState() {
    const { col, row, visibleCols, visibleRows } = this.viewport;
    const { cellWidth, cellHeight } = this.layout;
    const { xMin, xMax, yMin, yMax } = this.metadata.axes;
    const { left, top, right, bottom } = this.metadata.dataInsets;

    // Reserve space for facet strips (headers)
    const STRIP_WIDTH = 60;
    const STRIP_HEIGHT = 30;
    const grid_origin_x = STRIP_WIDTH + this.cellSpacing;
    const grid_origin_y = STRIP_HEIGHT + this.cellSpacing;

    const layoutState = {
      vis_x_min: xMin,
      vis_x_max: xMax,
      vis_y_min: yMin,
      vis_y_max: yMax,
      grid_origin_x,
      grid_origin_y,
      cell_width: cellWidth,
      cell_height: cellHeight,
      cell_spacing: this.cellSpacing,
      n_visible_cols: visibleCols,
      n_visible_rows: visibleRows,
      viewport_col_start: col,
      viewport_row_start: row,
      scroll_offset_x: 0,
      scroll_offset_y: 0,
      // Data area insets from WASM layout (space for axis chrome)
      data_inset_left: left,
      data_inset_top: top,
      data_inset_right: right,
      data_inset_bottom: bottom,
    };

    // Removed 60fps logging (60 lines/sec at 60fps)
    return layoutState;
  }

  // ── Chrome Generation ──────────────────────────────────────────────────

  /**
   * Generate chrome rects for visible facets.
   * Returns object with category keys (panel_backgrounds, strip_backgrounds, axis_lines, etc).
   * Matches GGRS-generated chrome structure for Phase 2 compatibility.
   */
  renderChrome() {
    const { col, row, visibleCols, visibleRows } = this.viewport;
    const { cellWidth, cellHeight } = this.layout;
    const { totalCols, totalRows } = this.metadata.grid;
    const { xMin, xMax, yMin, yMax } = this.metadata.axes;
    const { panelFill, borderColor, gridLineColor, axisLineColor, tickMarkColor, textColor } = this.metadata.chrome;

    const chrome = {
      panel_backgrounds: [],
      strip_backgrounds_top: [],
      strip_backgrounds_left: [],
      grid_lines: [],
      panel_borders: [],
      axis_lines: [],
      tick_marks: [],
    };

    // Text layers (separate from rect layers)
    const textLayers = {
      strip_labels_top: [],
      strip_labels_left: [],
      axis_labels: [],
    };

    const startCol = Math.floor(col);
    const startRow = Math.floor(row);
    const endCol = Math.min(totalCols, Math.ceil(col + visibleCols));
    const endRow = Math.min(totalRows, Math.ceil(row + visibleRows));

    const STRIP_HEIGHT = 30; // Top strip height
    const STRIP_WIDTH = 60;  // Left strip width
    const TICK_LENGTH = 6;

    // Data area insets from WASM layout
    const { left: insetLeft, top: insetTop, right: insetRight, bottom: insetBottom } = this.metadata.dataInsets;

    // Grid origin offset to reserve space for strips
    const grid_origin_x = STRIP_WIDTH + this.cellSpacing;
    const grid_origin_y = STRIP_HEIGHT + this.cellSpacing;

    for (let ri = startRow; ri < endRow; ri++) {
      for (let ci = startCol; ci < endCol; ci++) {
        const offsetCol = ci - col;
        const offsetRow = ri - row;

        // Data panels start at grid_origin to make room for strips
        const x = grid_origin_x + offsetCol * (cellWidth + this.cellSpacing);
        const y = grid_origin_y + offsetRow * (cellHeight + this.cellSpacing);

        // ── Panel background ──
        chrome.panel_backgrounds.push({
          x, y,
          width: cellWidth,
          height: cellHeight,
          color: panelFill,
        });

        // ── Panel border ──
        chrome.panel_borders.push({
          x, y,
          width: cellWidth,
          height: cellHeight,
          color: borderColor,
        });

        // ── Axis lines (bottom and left of each panel) ──
        // X axis (bottom)
        chrome.axis_lines.push({
          x: x,
          y: y + cellHeight - insetBottom,
          width: cellWidth,
          height: 1,
          color: axisLineColor,
        });
        // Y axis (left)
        chrome.axis_lines.push({
          x: x + insetLeft,
          y: y,
          width: 1,
          height: cellHeight,
          color: axisLineColor,
        });

        // ── Tick marks (5 ticks per axis) ──
        const nTicks = 5;
        for (let i = 0; i < nTicks; i++) {
          const t = i / (nTicks - 1); // 0, 0.25, 0.5, 0.75, 1.0

          // X axis ticks (distributed across data area width)
          const dataAreaWidth = cellWidth - insetLeft - insetRight;
          const tickX = x + insetLeft + t * dataAreaWidth;
          chrome.tick_marks.push({
            x: tickX,
            y: y + cellHeight - insetBottom,
            width: 1,
            height: TICK_LENGTH,
            color: tickMarkColor,
          });

          // Y axis ticks (distributed across data area height)
          const dataAreaHeight = cellHeight - insetTop - insetBottom;
          const tickY = y + insetTop + t * dataAreaHeight;
          chrome.tick_marks.push({
            x: x + insetLeft - TICK_LENGTH,
            y: tickY,
            width: TICK_LENGTH,
            height: 1,
            color: tickMarkColor,
          });

          // ── Axis labels ──
          const xValue = xMin + t * (xMax - xMin);
          const yValue = yMax - t * (yMax - yMin); // Y axis inverted (top=max)

          textLayers.axis_labels.push({
            text: xValue.toFixed(0),
            x: tickX,
            y: y + cellHeight - insetBottom + TICK_LENGTH + 3,
            fontSize: 10,
            color: textColor,
            align: 'center',
          });

          textLayers.axis_labels.push({
            text: yValue.toFixed(0),
            x: x + insetLeft - TICK_LENGTH - 3,
            y: tickY,
            fontSize: 10,
            color: textColor,
            align: 'right',
          });
        }

        // ── Grid lines (between panels) ──
        if (ci < totalCols - 1) {
          chrome.grid_lines.push({
            x: x + cellWidth,
            y,
            width: this.cellSpacing,
            height: cellHeight,
            color: gridLineColor,
          });
        }
        if (ri < totalRows - 1) {
          chrome.grid_lines.push({
            x,
            y: y + cellHeight,
            width: cellWidth,
            height: this.cellSpacing,
            color: gridLineColor,
          });
        }
      }
    }

    // ── Facet strip headers (spanning across column/row) ──

    // Top headers: one bar per COLUMN spanning all visible rows
    const gridHeight = (endRow - startRow) * (cellHeight + this.cellSpacing) - this.cellSpacing;
    for (let ci = startCol; ci < endCol; ci++) {
      const offsetCol = ci - col;
      const x = grid_origin_x + offsetCol * (cellWidth + this.cellSpacing);

      // Strip background at top of canvas (not negative)
      chrome.strip_backgrounds_top.push({
        x,
        y: 0,
        width: cellWidth,
        height: STRIP_HEIGHT,
        color: '#F3F4F6', // Light gray
      });

      // Header label centered in strip
      textLayers.strip_labels_top.push({
        text: `Col ${ci}`,  // Phase 2: use actual facet values
        x: x + cellWidth / 2,
        y: STRIP_HEIGHT / 2,
        fontSize: 13,
        fontWeight: '600',
        color: textColor,
        align: 'center',
      });
    }

    // Left headers: one bar per ROW spanning all visible columns
    const gridWidth = (endCol - startCol) * (cellWidth + this.cellSpacing) - this.cellSpacing;
    for (let ri = startRow; ri < endRow; ri++) {
      const offsetRow = ri - row;
      const y = grid_origin_y + offsetRow * (cellHeight + this.cellSpacing);

      // Strip background at left edge of canvas (not negative)
      chrome.strip_backgrounds_left.push({
        x: 0,
        y,
        width: STRIP_WIDTH,
        height: cellHeight,
        color: '#F3F4F6', // Light gray
      });

      // Header label centered in strip
      textLayers.strip_labels_left.push({
        text: `Row ${ri}`,  // Phase 2: use actual facet values
        x: STRIP_WIDTH / 2,
        y: y + cellHeight / 2,
        fontSize: 13,
        fontWeight: '600',
        color: textColor,
        align: 'center',
      });
    }

    // Merge text layers into chrome for now (GPU will handle separately)
    chrome.strip_labels_top = textLayers.strip_labels_top;
    chrome.strip_labels_left = textLayers.strip_labels_left;
    chrome.axis_labels = textLayers.axis_labels;

    return chrome;
  }

  // ── Hit Testing (queries) ──────────────────────────────────────────────

  /**
   * Get facet (col, row) at canvas pixel coordinates.
   * Returns null if outside grid.
   */
  getFacetAt(canvasX, canvasY) {
    const { col, row } = this.viewport;
    const { cellWidth, cellHeight } = this.layout;
    const { totalCols, totalRows } = this.metadata.grid;

    const STRIP_WIDTH = 60;
    const STRIP_HEIGHT = 30;
    const grid_origin_x = STRIP_WIDTH + this.cellSpacing;
    const grid_origin_y = STRIP_HEIGHT + this.cellSpacing;

    // Subtract strip offset before computing facet indices
    const gridX = canvasX - grid_origin_x;
    const gridY = canvasY - grid_origin_y;

    // Check if outside grid area
    if (gridX < 0 || gridY < 0) {
      return null;
    }

    // Reverse pixel math (now relative to grid origin)
    const offsetCol = Math.floor(gridX / (cellWidth + this.cellSpacing));
    const offsetRow = Math.floor(gridY / (cellHeight + this.cellSpacing));

    const facetCol = Math.floor(col) + offsetCol;
    const facetRow = Math.floor(row) + offsetRow;

    if (facetCol < 0 || facetCol >= totalCols || facetRow < 0 || facetRow >= totalRows) {
      return null;
    }

    return { col: facetCol, row: facetRow };
  }

  /**
   * Get zone at canvas pixel coordinates.
   * Returns 'left' (row strip), 'top' (col strip), 'data' (inside grid), or 'outside'.
   */
  getZoneAt(canvasX, canvasY) {
    if (canvasX < 0 || canvasX >= this.canvasWidth || canvasY < 0 || canvasY >= this.canvasHeight) {
      return 'outside';
    }

    const STRIP_WIDTH = 60;
    const STRIP_HEIGHT = 30;
    const grid_origin_x = STRIP_WIDTH + this.cellSpacing;
    const grid_origin_y = STRIP_HEIGHT + this.cellSpacing;

    // Check zones from outside in
    if (canvasX < grid_origin_x) {
      return 'left';  // Row strip (left side)
    }
    if (canvasY < grid_origin_y) {
      return 'top';   // Column strip (top side)
    }
    return 'data';    // Inside grid area
  }

  /**
   * Get data points near canvas pixel coordinates (Phase 2).
   * Requires spatial index to be built.
   */
  getPointsNear(canvasX, canvasY, radius = 5) {
    if (!this.spatialIndex) {
      return [];
    }
    // Phase 2: spatial index query
    return this.spatialIndex.queryCircle(canvasX, canvasY, radius);
  }

  // ── Incremental Facet Loading ──────────────────────────────────────────

  /**
   * Calculate which facets are currently visible in the viewport.
   * Returns integer range (inclusive start, exclusive end).
   */
  getVisibleFacetRange() {
    const { col, row, visibleCols, visibleRows } = this.viewport;
    const { totalCols, totalRows } = this.metadata.grid;

    return {
      colStart: Math.floor(col),
      colEnd: Math.min(Math.ceil(col + visibleCols), totalCols),
      rowStart: Math.floor(row),
      rowEnd: Math.min(Math.ceil(row + visibleRows), totalRows),
    };
  }

  /**
   * Calculate which facets should be loaded (visible + buffer zone).
   * Buffer zone is dynamic: 25% of visible facet count on each edge.
   * Returns integer range (inclusive start, exclusive end).
   */
  getNeededFacetRange() {
    const visible = this.getVisibleFacetRange();
    const { totalCols, totalRows } = this.metadata.grid;
    const { visibleCols, visibleRows } = this.viewport;

    // Dynamic buffer: 25% of visible dimension (adapts to zoom level)
    const bufferCols = Math.ceil(visibleCols * 0.25);
    const bufferRows = Math.ceil(visibleRows * 0.25);

    return {
      colStart: Math.max(0, visible.colStart - bufferCols),
      colEnd: Math.min(totalCols, visible.colEnd + bufferCols),
      rowStart: Math.max(0, visible.rowStart - bufferRows),
      rowEnd: Math.min(totalRows, visible.rowEnd + bufferRows),
    };
  }

  /**
   * Create a history snapshot for an in-flight load.
   * Returns unique ID for this load.
   */
  createLoadSnapshot(neededRange) {
    const id = this._nextLoadId++;
    const snapshot = {
      id,
      viewport: { ...this.viewport },
      layout: {
        cellWidth: this.layout.cellWidth,
        cellHeight: this.layout.cellHeight,
        stripWidth: this.layout.stripWidth,
        stripHeight: this.layout.stripHeight,
      },
      neededRange: { ...neededRange },
      timestamp: performance.now(),
    };
    this._loadHistory.push(snapshot);
    console.log(`[PlotState] Created load snapshot #${id} for range cols [${neededRange.colStart}, ${neededRange.colEnd}), rows [${neededRange.rowStart}, ${neededRange.rowEnd})`);
    return id;
  }

  /**
   * Retrieve a load snapshot by ID.
   */
  getLoadSnapshot(id) {
    return this._loadHistory.find(entry => entry.id === id);
  }

  /**
   * Remove a load snapshot after use.
   */
  removeLoadSnapshot(id) {
    const index = this._loadHistory.findIndex(entry => entry.id === id);
    if (index !== -1) {
      this._loadHistory.splice(index, 1);
      console.log(`[PlotState] Removed load snapshot #${id} (${this._loadHistory.length} remaining)`);
    }
  }

  /**
   * Check if new facets need loading based on current viewport.
   * Implements sliding window: triggers callback if needed range differs from loaded.
   * Called automatically on viewport changes (scroll/zoom).
   */
  checkAndLoadNewFacets() {
    console.log(`[PlotState] checkAndLoadNewFacets() called`);
    console.log(`[PlotState]   onLoadFacets callback: ${this.onLoadFacets ? 'registered' : 'NOT REGISTERED'}`);

    if (!this.onLoadFacets) {
      console.warn(`[PlotState]   ⚠️ No load callback registered - exiting`);
      return; // No load callback registered
    }

    const needed = this.getNeededFacetRange();
    const loaded = this.loadedFacets;

    console.log(`[PlotState]   Needed range: cols [${needed.colStart}, ${needed.colEnd}), rows [${needed.rowStart}, ${needed.rowEnd})`);
    console.log(`[PlotState]   Loaded range: cols [${loaded.colStart}, ${loaded.colEnd}), rows [${loaded.rowStart}, ${loaded.rowEnd})`);

    // Check if needed range is different from loaded range
    const rangeChanged =
      needed.colStart !== loaded.colStart ||
      needed.colEnd !== loaded.colEnd ||
      needed.rowStart !== loaded.rowStart ||
      needed.rowEnd !== loaded.rowEnd;

    console.log(`[PlotState]   Range changed: ${rangeChanged}`);

    if (!rangeChanged) {
      console.log(`[PlotState]   → No change, skipping`);
      return; // Needed range matches loaded range - no update needed
    }

    console.log(`[PlotState]   → TRIGGERING onLoadFacets callback`);

    // Create snapshot of current viewport/layout state
    const loadId = this.createLoadSnapshot(needed);

    // Trigger callback with needed range and load ID
    // Callback will compute overlap, filter points, and load new rectangles
    // Load ID allows correct placement even if viewport changes during load
    this.onLoadFacets(needed, loadId);

    // Note: loadedFacets will be updated by callback after data loads
  }

  /**
   * Set the loaded facet range (called after data loading completes).
   * This is the ONLY method that should update loadedFacets (single source of truth).
   *
   * @param {number} colStart
   * @param {number} colEnd
   * @param {number} rowStart
   * @param {number} rowEnd
   * @param {boolean} force - If false, won't overwrite if loadedFacets has been modified from default
   */
  markFacetsLoaded(colStart, colEnd, rowStart, rowEnd, force = true) {
    const current = this.loadedFacets;
    const isDefault = current.colEnd === 0 && current.rowEnd === 0;

    // If not forcing and loadedFacets has been updated from default, don't overwrite
    // (prevents race condition where initial render overwrites viewport change)
    if (!force && !isDefault) {
      console.log(`[PlotState] markFacetsLoaded SKIPPED (already updated): current=[${current.colStart}, ${current.colEnd})×[${current.rowStart}, ${current.rowEnd}), requested=[${colStart}, ${colEnd})×[${rowStart}, ${rowEnd})`);
      return;
    }

    this.loadedFacets = {
      colStart,
      colEnd,
      rowStart,
      rowEnd,
    };
    console.log(`[PlotState] Loaded facets set: cols [${colStart}, ${colEnd}), rows [${rowStart}, ${rowEnd})`);
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  destroy() {
    // this.cancelAnimation(); // Commented out - animation system removed
    this.spatialIndex = null;
  }
}
