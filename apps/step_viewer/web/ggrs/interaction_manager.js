/**
 * InteractionManager - Event routing and zone detection for V3.
 *
 * Uses PlotState (JS) for all viewport math and metadata instead of WASM calls.
 * Zone-dependent zoom, scroll, pan, double-click reset, 200ms animation.
 *
 * Key interactions:
 * - Shift+wheel → Zoom (zone-dependent: left=height, top=width, data=both)
 * - Plain wheel → Vertical scroll
 * - Ctrl+wheel → Horizontal scroll
 * - Ctrl+drag → Pan in any direction
 * - Double-click → Reset view to initial state
 */

export class InteractionManager {
    /**
     * @param {string} containerId
     * @param {import('./ggrs_gpu_v3.js').GgrsGpuV3} gpu
     * @param {HTMLElement} interactionDiv
     * @param {import('./plot_state.js').PlotState} plotState
     * @param {Function} onChromeRebuild - Called when chrome needs rebuilding
     */
    constructor(containerId, gpu, interactionDiv, plotState, onChromeRebuild) {
        this.containerId = containerId;
        this.gpu = gpu;
        this.interactionDiv = interactionDiv;
        this.plotState = plotState;
        this.onChromeRebuild = onChromeRebuild;

        // Drag state
        this.isDragging = false;
        this.lastMouseX = 0;
        this.lastMouseY = 0;

        // Event listeners (for cleanup)
        this.listeners = [];

        // Store initial viewport for reset
        this._initialViewport = {
            col: plotState.viewport.col,
            row: plotState.viewport.row,
            visibleCols: plotState.viewport.visibleCols,
            visibleRows: plotState.viewport.visibleRows,
        };

        this._attachListeners();
    }

    /**
     * Detect interaction zone from mouse position.
     * Uses PlotState.getZoneAt() for consistent zone detection.
     * @param {number} x - Mouse X in canvas coordinates
     * @param {number} y - Mouse Y in canvas coordinates
     * @returns {"left" | "top" | "data" | "outside"}
     */
    detectZone(x, y) {
        return this.plotState.getZoneAt(x, y);
    }

    // ── COMMENTED OUT: Sync and rebuild (replaced by continuous render loop) ──
    //
    // Old approach: scroll event → immediate sync + chrome rebuild
    // New approach: scroll event → update viewport state only
    //               continuous render loop → sync at 60fps
    //               data chunk arrives → rebuild chrome
    //
    // /**
    //  * Sync viewport state to GPU and rebuild chrome.
    //  * Uses bootstrap function (not direct GPU call) to get smooth scrolling.
    //  */
    // _syncAndRebuild(needsChrome) {
    //     // Call bootstrap function to get GPU-side smooth scrolling
    //     // (direct gpu.syncLayoutState() bypasses animation logic)
    //     window.ggrsV3.ggrsV3SyncLayout(this.containerId);
    //
    //     if (needsChrome && this.onChromeRebuild) {
    //         this.onChromeRebuild();
    //     }
    // }

    /**
     * Attach event listeners to interaction div.
     */
    _attachListeners() {
        // Wheel events
        const onWheel = (e) => {
            e.preventDefault();

            const rect = this.interactionDiv.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            const zone = this.detectZone(x, y);

            // Browser swaps deltaY→deltaX when Shift held
            const delta = e.deltaY !== 0 ? e.deltaY : e.deltaX;

            if (e.shiftKey) {
                // ── Shift+wheel → Zoom ──
                // Simplified: just update viewport state, continuous render loop handles smoothness
                const zoomFactor = delta > 0 ? 1.25 : 0.8; // scroll down = zoom out, up = zoom in

                const vp = this.plotState.viewport;
                let targetVisCols = vp.visibleCols;
                let targetVisRows = vp.visibleRows;

                if (zone === 'left') {
                    // Left strip: height only
                    targetVisRows *= zoomFactor;
                } else if (zone === 'top') {
                    // Top strip: width only
                    targetVisCols *= zoomFactor;
                } else {
                    // Data zone or outside: both
                    targetVisCols *= zoomFactor;
                    targetVisRows *= zoomFactor;
                }

                // Minimum visible extent
                targetVisCols = Math.max(0.1, targetVisCols);
                targetVisRows = Math.max(0.1, targetVisRows);

                // Just update viewport - continuous render loop handles rest
                this.plotState.setViewport(vp.col, vp.row, targetVisCols, targetVisRows);
            } else if (e.ctrlKey) {
                // ── Ctrl+wheel → Horizontal scroll ──
                // Relative step: 10% of visible facets (adapts to zoom level)
                const vp = this.plotState.viewport;
                const step = vp.visibleCols * 0.1;
                const panAmount = delta > 0 ? step : -step;
                const { totalCols } = this.plotState.metadata.grid;
                const targetCol = Math.max(0, Math.min(
                    vp.col + panAmount,
                    totalCols - vp.visibleCols,
                ));

                // Just update viewport - continuous render loop handles rest
                this.plotState.setViewport(targetCol, vp.row, vp.visibleCols, vp.visibleRows);
            } else {
                // ── Plain wheel → Vertical scroll ──
                // Relative step: 10% of visible facets (adapts to zoom level)
                const vp = this.plotState.viewport;
                const step = vp.visibleRows * 0.1;
                const panAmount = delta > 0 ? step : -step;
                const direction = delta > 0 ? 'DOWN' : 'UP';
                const { totalRows } = this.plotState.metadata.grid;
                const targetRow = Math.max(0, Math.min(
                    vp.row + panAmount,
                    totalRows - vp.visibleRows,
                ));

                console.log(`[InteractionManager] Scroll ${direction}: step=${step.toFixed(2)}, currentRow=${vp.row.toFixed(2)}, targetRow=${targetRow.toFixed(2)}`);

                // Just update viewport - continuous render loop handles rest
                this.plotState.setViewport(vp.col, targetRow, vp.visibleCols, vp.visibleRows);
            }
        };
        this.interactionDiv.addEventListener('wheel', onWheel, { passive: false });
        this.listeners.push({ element: this.interactionDiv, type: 'wheel', handler: onWheel });

        // ── Ctrl+drag → Pan ──
        const onMouseDown = (e) => {
            if (!e.ctrlKey) return; // Only Ctrl+drag starts pan

            e.preventDefault();
            this.isDragging = true;
            this.lastMouseX = e.clientX;
            this.lastMouseY = e.clientY;
        };
        this.interactionDiv.addEventListener('mousedown', onMouseDown);
        this.listeners.push({ element: this.interactionDiv, type: 'mousedown', handler: onMouseDown });

        const onMouseMove = (e) => {
            if (!this.isDragging) return;

            const dx = e.clientX - this.lastMouseX;
            const dy = e.clientY - this.lastMouseY;
            this.lastMouseX = e.clientX;
            this.lastMouseY = e.clientY;

            // Convert pixel delta to viewport delta
            const { cellWidth, cellHeight } = this.plotState.layout;
            const vp = this.plotState.viewport;
            const colDelta = -dx / (cellWidth + this.plotState.cellSpacing);
            const rowDelta = -dy / (cellHeight + this.plotState.cellSpacing);

            // Just update viewport - continuous render loop handles rest
            this.plotState.setViewport(
                vp.col + colDelta,
                vp.row + rowDelta,
                vp.visibleCols,
                vp.visibleRows,
            );
        };
        this.interactionDiv.addEventListener('mousemove', onMouseMove);
        this.listeners.push({ element: this.interactionDiv, type: 'mousemove', handler: onMouseMove });

        const onMouseUp = (e) => {
            if (!this.isDragging) return;
            this.isDragging = false;
        };
        this.interactionDiv.addEventListener('mouseup', onMouseUp);
        this.listeners.push({ element: this.interactionDiv, type: 'mouseup', handler: onMouseUp });

        // ── Double-click → Reset ──
        const onDblClick = (e) => {
            e.preventDefault();
            const init = this._initialViewport;

            // Just update viewport - continuous render loop handles rest
            this.plotState.setViewport(init.col, init.row, init.visibleCols, init.visibleRows);
        };
        this.interactionDiv.addEventListener('dblclick', onDblClick);
        this.listeners.push({ element: this.interactionDiv, type: 'dblclick', handler: onDblClick });

        // ── Escape → Cancel drag ──
        const onKeyDown = (e) => {
            if (e.key === 'Escape' && this.isDragging) {
                this.isDragging = false;
            }
        };
        document.addEventListener('keydown', onKeyDown);
        this.listeners.push({ element: document, type: 'keydown', handler: onKeyDown });

        console.log('[InteractionManager] Event listeners attached (viewport-driven)');
    }

    /**
     * Remove all event listeners (cleanup).
     */
    destroy() {
        for (const { element, type, handler } of this.listeners) {
            element.removeEventListener(type, handler);
        }
        this.listeners = [];
        console.log('[InteractionManager] Event listeners removed');
    }
}

console.log('[interaction_manager] V3 InteractionManager class loaded (PlotState-driven)');
