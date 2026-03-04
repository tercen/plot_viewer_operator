/**
 * PlotOrchestrator - State machine for plot initialization and lifecycle
 *
 * Ensures proper ordering of initialization steps and provides event-based
 * messaging for cross-component communication.
 *
 * States:
 *   UNINITIALIZED → WASM_READY → RENDERER_READY → GPU_READY →
 *   METADATA_READY → CHROME_READY → DATA_STREAMING → DATA_READY → READY
 *
 * Events:
 *   - state-changed: (state, metadata) → When state transitions
 *   - viewport-changed: (range) → When user scrolls/zooms
 *   - facets-loaded: (range) → When background facet load completes
 *   - error: (error, state) → When initialization fails at a state
 */

export class PlotOrchestrator {
  constructor(containerId) {
    this.containerId = containerId;
    this.state = 'UNINITIALIZED';
    this.listeners = new Map(); // event → Set<callback>
    this.stateData = {}; // Store data from each state
    this.error = null;
  }

  // ── State Machine ──────────────────────────────────────────────────────

  /**
   * Get current state.
   */
  getState() {
    return this.state;
  }

  /**
   * Transition to a new state.
   * Validates state order and emits state-changed event.
   */
  setState(newState, metadata = {}) {
    const validTransitions = {
      UNINITIALIZED: ['WASM_READY'],
      WASM_READY: ['RENDERER_READY'],
      RENDERER_READY: ['GPU_READY'],
      GPU_READY: ['METADATA_READY'],
      METADATA_READY: ['CHROME_READY'],
      CHROME_READY: ['DATA_STREAMING'],
      DATA_STREAMING: ['DATA_READY'],
      DATA_READY: ['READY'],
      READY: ['DATA_STREAMING'], // Allow re-streaming
    };

    const allowed = validTransitions[this.state] || [];
    if (!allowed.includes(newState)) {
      const error = `Invalid state transition: ${this.state} → ${newState}`;
      console.error(`[PlotOrchestrator] ${error}`);
      this.error = error;
      this.emit('error', error, this.state);
      return false;
    }

    const oldState = this.state;
    this.state = newState;
    this.stateData[newState] = metadata;

    console.log(`[PlotOrchestrator] ${oldState} → ${newState}`, metadata);
    this.emit('state-changed', newState, metadata);
    return true;
  }

  /**
   * Mark initialization as failed at current state.
   */
  setError(error) {
    this.error = error;
    console.error(`[PlotOrchestrator] ERROR at ${this.state}:`, error);
    this.emit('error', error, this.state);
  }

  /**
   * Check if a state has been reached.
   */
  hasReached(state) {
    const order = [
      'UNINITIALIZED', 'WASM_READY', 'RENDERER_READY', 'GPU_READY',
      'METADATA_READY', 'CHROME_READY', 'DATA_STREAMING', 'DATA_READY', 'READY',
    ];
    const currentIdx = order.indexOf(this.state);
    const targetIdx = order.indexOf(state);
    return currentIdx >= targetIdx;
  }

  /**
   * Get data from a specific state.
   */
  getStateData(state) {
    return this.stateData[state];
  }

  // ── Event Messaging ────────────────────────────────────────────────────

  /**
   * Register event listener.
   *
   * @param {string} event - Event name
   * @param {Function} callback - Callback function
   * @returns {Function} Unsubscribe function
   */
  on(event, callback) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event).add(callback);

    // Return unsubscribe function
    return () => {
      const callbacks = this.listeners.get(event);
      if (callbacks) {
        callbacks.delete(callback);
      }
    };
  }

  /**
   * Register one-time event listener.
   */
  once(event, callback) {
    const unsubscribe = this.on(event, (...args) => {
      unsubscribe();
      callback(...args);
    });
    return unsubscribe;
  }

  /**
   * Emit event to all listeners.
   */
  emit(event, ...args) {
    const callbacks = this.listeners.get(event);
    if (callbacks) {
      callbacks.forEach(cb => {
        try {
          cb(...args);
        } catch (error) {
          console.error(`[PlotOrchestrator] Error in ${event} listener:`, error);
        }
      });
    }
  }

  /**
   * Remove all listeners for an event (or all events if no event specified).
   */
  off(event = null) {
    if (event) {
      this.listeners.delete(event);
    } else {
      this.listeners.clear();
    }
  }

  // ── Initialization Helpers ─────────────────────────────────────────────

  /**
   * Ensure a state is reached before proceeding.
   * Throws error if state hasn't been reached yet.
   */
  requireState(state) {
    if (!this.hasReached(state)) {
      throw new Error(`PlotOrchestrator: ${state} required but current state is ${this.state}`);
    }
  }

  /**
   * Wait for a state to be reached (async).
   * Returns immediately if state already reached, otherwise waits for state-changed event.
   */
  async waitForState(state, timeoutMs = 30000) {
    if (this.hasReached(state)) {
      return;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        unsubscribe();
        reject(new Error(`Timeout waiting for state ${state} (current: ${this.state})`));
      }, timeoutMs);

      const unsubscribe = this.on('state-changed', (newState) => {
        if (newState === state || this.hasReached(state)) {
          clearTimeout(timeout);
          unsubscribe();
          resolve();
        }
      });

      // Also listen for errors
      const errorUnsubscribe = this.on('error', (error) => {
        clearTimeout(timeout);
        unsubscribe();
        errorUnsubscribe();
        reject(new Error(`PlotOrchestrator error: ${error}`));
      });
    });
  }

  // ── Cleanup ────────────────────────────────────────────────────────────

  destroy() {
    this.off(); // Remove all listeners
    this.stateData = {};
    this.state = 'UNINITIALIZED';
    this.error = null;
  }
}

console.log('[plot_orchestrator] PlotOrchestrator class loaded');
