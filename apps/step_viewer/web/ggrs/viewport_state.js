/**
 * ViewportState - JS viewport management module.
 *
 * Extracted from test_streaming.html reference implementation.
 * Manages fractional viewport state, cell dimension derivation,
 * chrome generation, and smooth animation.
 *
 * The viewport is defined by 4 floats:
 * - viewportCol, viewportRow: top-left corner (fractional facet index)
 * - visibleCols, visibleRows: how many facets are visible (fractional)
 *
 * Cell dimensions are DERIVED from viewport extent and canvas size:
 *   cellWidth = (canvasWidth - (visibleCols - 1) * cellSpacing) / visibleCols
 */

export class ViewportState {
    /**
     * @param {Object} config
     * @param {number} config.canvasWidth
     * @param {number} config.canvasHeight
     * @param {number} config.cellSpacing - Pixel gap between facet cells
     * @param {number} config.initialVisibleCols - Initial fractional cols visible
     * @param {number} config.initialVisibleRows - Initial fractional rows visible
     */
    constructor(config) {
        // Canvas dimensions
        this.canvasWidth = config.canvasWidth;
        this.canvasHeight = config.canvasHeight;
        this.cellSpacing = config.cellSpacing || 10;

        // Grid dimensions (set later via setGridConfig)
        this.totalCols = 1;
        this.totalRows = 1;

        // Axis ranges (data space)
        this.xMin = 0;
        this.xMax = 100;
        this.yMin = 0;
        this.yMax = 100;

        // Fractional viewport state
        this.viewportCol = 0.0;
        this.viewportRow = 0.0;
        this.visibleCols = config.initialVisibleCols || 3.0;
        this.visibleRows = config.initialVisibleRows || 3.0;

        // Initial values (for reset)
        this._initialVisibleCols = this.visibleCols;
        this._initialVisibleRows = this.visibleRows;

        // Animation state
        this._isAnimating = false;
        this._animationStartTime = 0;
        this._animationDuration = 200; // ms
        this._animStartCol = 0;
        this._animStartRow = 0;
        this._animStartVisCols = 0;
        this._animStartVisRows = 0;
        this._animTargetCol = 0;
        this._animTargetRow = 0;
        this._animTargetVisCols = 0;
        this._animTargetVisRows = 0;
        this._animOnFrame = null;
        this._animOnComplete = null;
        this._animRafId = null;
    }

    /**
     * Configure grid dimensions and axis ranges.
     * Call this after initPlotStream returns metadata.
     */
    setGridConfig(config) {
        this.totalCols = config.totalCols || 1;
        this.totalRows = config.totalRows || 1;
        this.xMin = config.xMin ?? 0;
        this.xMax = config.xMax ?? 100;
        this.yMin = config.yMin ?? 0;
        this.yMax = config.yMax ?? 100;

        // Adjust visible extent if it exceeds total grid
        if (this.visibleCols > this.totalCols) {
            this.visibleCols = this.totalCols;
        }
        if (this.visibleRows > this.totalRows) {
            this.visibleRows = this.totalRows;
        }

        console.log(`[ViewportState] Grid config: ${this.totalCols}x${this.totalRows}, ` +
            `axes: x=[${this.xMin}, ${this.xMax}], y=[${this.yMin}, ${this.yMax}]`);
    }

    /**
     * Derive cell dimensions from fractional viewport extent.
     * @returns {{ cellWidth: number, cellHeight: number }}
     */
    deriveCellDimensions() {
        const totalSpacingX = (this.visibleCols - 1) * this.cellSpacing;
        const totalSpacingY = (this.visibleRows - 1) * this.cellSpacing;
        const cellWidth = (this.canvasWidth - totalSpacingX) / this.visibleCols;
        const cellHeight = (this.canvasHeight - totalSpacingY) / this.visibleRows;
        return { cellWidth, cellHeight };
    }

    /**
     * Build full layout state object for gpu.syncLayoutState().
     * @returns {Object} LayoutState JSON-serializable object
     */
    buildLayoutState() {
        const { cellWidth, cellHeight } = this.deriveCellDimensions();

        return {
            vis_x_min: this.xMin,
            vis_x_max: this.xMax,
            vis_y_min: this.yMin,
            vis_y_max: this.yMax,
            grid_origin_x: 0,
            grid_origin_y: 0,
            cell_width: cellWidth,
            cell_height: cellHeight,
            cell_spacing: this.cellSpacing,
            n_visible_cols: this.visibleCols,
            n_visible_rows: this.visibleRows,
            viewport_col_start: this.viewportCol,
            viewport_row_start: this.viewportRow,
            scroll_offset_x: 0,
            scroll_offset_y: 0,
        };
    }

    /**
     * Set viewport position and clamp to valid range.
     * @param {number} col - Top-left column (fractional)
     * @param {number} row - Top-left row (fractional)
     * @param {number} [visCols] - Visible columns (fractional)
     * @param {number} [visRows] - Visible rows (fractional)
     */
    setViewport(col, row, visCols, visRows) {
        if (visCols !== undefined) this.visibleCols = visCols;
        if (visRows !== undefined) this.visibleRows = visRows;

        // Clamp minimum visible extent
        this.visibleCols = Math.max(0.1, this.visibleCols);
        this.visibleRows = Math.max(0.1, this.visibleRows);

        // Clamp position: viewport must stay within grid bounds
        this.viewportCol = Math.max(0, Math.min(col, this.totalCols - this.visibleCols));
        this.viewportRow = Math.max(0, Math.min(row, this.totalRows - this.visibleRows));

        // If viewport is wider than grid, snap to 0
        if (this.visibleCols >= this.totalCols) this.viewportCol = 0;
        if (this.visibleRows >= this.totalRows) this.viewportRow = 0;
    }

    /**
     * Animate viewport change with ease-out cubic.
     * @param {number} targetCol
     * @param {number} targetRow
     * @param {number} targetVisCols
     * @param {number} targetVisRows
     * @param {Function} onFrame - Called every animation frame
     * @param {Function} [onComplete] - Called when animation finishes
     */
    animateTo(targetCol, targetRow, targetVisCols, targetVisRows, onFrame, onComplete) {
        if (this._isAnimating) {
            // Cancel current animation, snap to current interpolated values
            if (this._animRafId) cancelAnimationFrame(this._animRafId);
            this._isAnimating = false;
        }

        this._animStartCol = this.viewportCol;
        this._animStartRow = this.viewportRow;
        this._animStartVisCols = this.visibleCols;
        this._animStartVisRows = this.visibleRows;
        this._animTargetCol = targetCol;
        this._animTargetRow = targetRow;
        this._animTargetVisCols = targetVisCols;
        this._animTargetVisRows = targetVisRows;
        this._animOnFrame = onFrame;
        this._animOnComplete = onComplete;

        this._isAnimating = true;
        this._animationStartTime = performance.now();

        const animate = (currentTime) => {
            const elapsed = currentTime - this._animationStartTime;
            const progress = Math.min(elapsed / this._animationDuration, 1.0);
            const eased = 1 - Math.pow(1 - progress, 3); // Ease-out cubic

            // Interpolate
            this.viewportCol = this._animStartCol + (this._animTargetCol - this._animStartCol) * eased;
            this.viewportRow = this._animStartRow + (this._animTargetRow - this._animStartRow) * eased;
            this.visibleCols = this._animStartVisCols + (this._animTargetVisCols - this._animStartVisCols) * eased;
            this.visibleRows = this._animStartVisRows + (this._animTargetVisRows - this._animStartVisRows) * eased;

            if (this._animOnFrame) this._animOnFrame();

            if (progress < 1.0) {
                this._animRafId = requestAnimationFrame(animate);
            } else {
                // Snap to final values
                this.setViewport(
                    this._animTargetCol,
                    this._animTargetRow,
                    this._animTargetVisCols,
                    this._animTargetVisRows,
                );
                this._isAnimating = false;
                if (this._animOnFrame) this._animOnFrame();
                if (this._animOnComplete) this._animOnComplete();
            }
        };

        this._animRafId = requestAnimationFrame(animate);
    }

    /**
     * Reset viewport to initial state (show all facets from top-left).
     */
    reset() {
        this.viewportCol = 0.0;
        this.viewportRow = 0.0;
        this.visibleCols = Math.min(this._initialVisibleCols, this.totalCols);
        this.visibleRows = Math.min(this._initialVisibleRows, this.totalRows);
    }

    get isAnimating() {
        return this._isAnimating;
    }

    /**
     * Generate chrome rects for visible facets.
     * @returns {{ panel_backgrounds: Array, grid_lines: Array }}
     */
    renderChrome() {
        const { cellWidth, cellHeight } = this.deriveCellDimensions();
        const chrome = {
            panel_backgrounds: [],
            grid_lines: [],
        };

        // Which facets are visible (including partial)?
        const startFacetCol = Math.floor(this.viewportCol);
        const endFacetCol = Math.ceil(this.viewportCol + this.visibleCols);
        const startFacetRow = Math.floor(this.viewportRow);
        const endFacetRow = Math.ceil(this.viewportRow + this.visibleRows);

        for (let facetRow = startFacetRow; facetRow < endFacetRow; facetRow++) {
            for (let facetCol = startFacetCol; facetCol < endFacetCol; facetCol++) {
                if (facetCol >= this.totalCols || facetRow >= this.totalRows) continue;

                // Position relative to viewport (same formula as GPU shader)
                const pc = facetCol - this.viewportCol;
                const pr = facetRow - this.viewportRow;

                let x = pc * (cellWidth + this.cellSpacing);
                let y = pr * (cellHeight + this.cellSpacing);
                let width = cellWidth;
                let height = cellHeight;

                // Clip to canvas bounds
                if (x < 0) { width += x; x = 0; }
                if (y < 0) { height += y; y = 0; }
                if (x + width > this.canvasWidth) { width = this.canvasWidth - x; }
                if (y + height > this.canvasHeight) { height = this.canvasHeight - y; }

                if (width > 0 && height > 0) {
                    chrome.panel_backgrounds.push({
                        x, y, width, height,
                        fill: '#f9f9f9',
                    });

                    chrome.grid_lines.push(
                        { x, y, width, height: 1, color: '#cccccc' },
                        { x, y: y + height, width, height: 1, color: '#cccccc' },
                        { x, y, width: 1, height, color: '#cccccc' },
                        { x: x + width, y, width: 1, height, color: '#cccccc' },
                    );
                }
            }
        }

        return chrome;
    }

    /**
     * Destroy animation state (cleanup).
     */
    destroy() {
        if (this._animRafId) {
            cancelAnimationFrame(this._animRafId);
            this._animRafId = null;
        }
        this._isAnimating = false;
    }
}

console.log('[viewport_state] ViewportState class loaded');
