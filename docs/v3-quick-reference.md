# GGRS V3 Quick Reference

Quick reference for working with the V3 architecture.

---

## Dart API (ggrs_service_v3.dart)

### Basic Usage

```dart
final ggrsService = serviceLocator<GgrsServiceV3>();

// Set Tercen credentials (once at app start)
ggrsService.setTercenCredentials(serviceUri, token);

// Render a plot
await ggrsService.render(
  'plot-container',
  plotStateProvider,
  width: 800,
  height: 600,
);
```

### Monitoring Progress

```dart
// Listen to phase changes
ggrsService.addListener(() {
  print('Phase: ${ggrsService.phase}');
  print('Error: ${ggrsService.error}');
});
```

---

## JavaScript API (bootstrap_v3.js)

### Manual Coordinator Control (Advanced)

```javascript
// Update coordinator context (triggers render)
ggrsV3.ggrsV3UpdateContext('plot-container', {
  xMin: 0.0,
  xMax: 10.0,
  yMin: 0.0,
  yMax: 10.0,
  dataXMin: 1.0,
  dataXMax: 9.0,
  dataYMin: 1.0,
  dataYMax: 9.0,
  nColFacets: 1,
  nRowFacets: 1,
});

// Invalidate specific layers
ggrsV3.ggrsV3InvalidateLayers('plot-container', [
  'chrome:grid_lines',
  'chrome:axis_lines'
]);

// Listen to progress
ggrsV3.ggrsV3AddProgressListener('plot-container', (event) => {
  if (event.complete) {
    console.log('Render complete!');
  } else {
    console.log(`Layer ${event.layer}: ${event.status}`);
  }
});
```

---

## WASM API (Rust)

### Interaction Handlers

```rust
// In lib.rs - create a new handler
let handler = Box::new(ZoomHandler::new(layout_manager_rc));

// Start interaction
let result = handler.on_start(
    InteractionZone::DataGrid,
    x, y,
    &json!({"delta": -120})
)?;

// Handle result
match result {
    InteractionResult::ViewUpdate(snapshot) => {
        // Apply layout state update
    }
    InteractionResult::NoChange => {
        // Keep accumulating
    }
    _ => {}
}
```

### Adding a Custom Handler

```rust
// 1. Implement InteractionHandler trait
pub struct MyHandler {
    layout_manager: Rc<RefCell<LayoutManager>>,
    // ... custom state
}

impl InteractionHandler for MyHandler {
    fn on_start(&mut self, zone, x, y, params) -> Result<InteractionResult, String> {
        // Your logic here
        Ok(InteractionResult::NoChange)
    }

    fn on_move(&mut self, dx, dy, x, y, params) -> Result<InteractionResult, String> {
        // Your logic here
        Ok(InteractionResult::ViewUpdate(snapshot_json))
    }

    fn on_end(&mut self) -> Result<InteractionResult, String> {
        Ok(InteractionResult::Committed)
    }

    fn on_cancel(&mut self) -> InteractionResult {
        InteractionResult::Cancelled
    }

    fn name(&self) -> &str {
        "MyHandler"
    }

    fn is_composable(&self) -> bool {
        false
    }
}

// 2. Register in lib.rs interaction_start()
"MyHandler" => Box::new(MyHandler::new(mgr_rc)),
```

---

## RenderCoordinator (JavaScript)

### Creating a Custom Layer

```javascript
export class MyCustomLayer extends RenderLayer {
    constructor(renderer) {
        super('my_layer', 40); // name, priority
        this.dependencies = ['viewstate']; // depends on viewstate
        this.renderer = renderer;
    }

    async render(ctx) {
        console.log('[MyCustomLayer] Rendering...');

        // Access shared context
        const layoutInfo = ctx.layoutInfo;
        const gpu = ctx.gpu;

        // Do your rendering
        // ...

        this.state = 'complete';
    }
}

// Register in bootstrap_v3.js
const myLayer = new MyCustomLayer(renderer);
coordinator.registerLayer(myLayer);
```

### Layer Priorities (Lower = Render First)

- 10: LayoutLayer (geometry computation)
- 15: ViewStateLayer (state creation)
- 30: ChromeLayers (backgrounds, axes, grid)
- 40: **Custom layers** (annotations, overlays)
- 60: DataLayer (data points)

---

## InteractionManager (JavaScript)

### Handler Selection Logic

```javascript
// Wheel events
Shift + wheel → Zoom
Ctrl + wheel → PanX (not implemented yet)
Wheel → PanY (not implemented yet)

// Mouse events
Ctrl + drag → Pan
Alt + drag → DragSelect (not implemented yet)
Plain drag → no handler (future: lasso)

// Keyboard
Double-click → Reset
Escape → Cancel active interaction
```

### Zone Detection

```javascript
const zone = interactionManager.detectZone(mouseX, mouseY);
// Returns: 'left' | 'top' | 'data' | 'outside'

// Zones affect handler behavior:
// - Left strip: Y-axis operations only
// - Top strip: X-axis operations only
// - Data grid: Both axes
// - Outside: Reject interaction
```

---

## Common Patterns

### Invalidating Layers After Zoom

```javascript
// InteractionManager automatically applies snapshots
// But if you need manual invalidation:
const zoomResult = renderer.zoom('x', 1); // Zoom in on X
const layoutState = JSON.parse(zoomResult);
if (layoutState.error) {
    console.error(layoutState.error);
} else {
    gpu.syncLayoutState(JSON.stringify(layoutState));
    // Invalidate geometric chrome layers
    coordinator.invalidateLayers([
        'chrome:grid_lines',
        'chrome:axis_lines',
        'chrome:tick_marks'
    ]);
}
```

### Cancelling a Render

```dart
// In Dart - increment generation counter
final newGen = ++_renderGeneration;

// Later in async code
_checkGen(newGen); // Throws if stale

void _checkGen(int gen) {
  if (gen != _renderGeneration) {
    throw Exception('Render cancelled (stale generation)');
  }
}
```

### Progress Tracking

```javascript
const coordinator = instance.coordinator;

coordinator.addListener((event) => {
    if (event.complete) {
        console.log('All layers rendered');
    } else if (event.layer) {
        console.log(`${event.layer}: ${event.status}`);
        // status: 'rendering' | 'complete' | 'failed'
    }
});
```

---

## Troubleshooting

### "No coordinator for container"
- Ensure `ggrsV3EnsureGpu()` was called before using coordinator API
- Check that containerId matches

### "Layout manager not initialized"
- Call `initLayout()` before using interaction handlers
- Or use ViewState approach (initView) for now

### "ViewStateLayer: no layoutInfo"
- Ensure LayoutLayer completed before ViewStateLayer
- Check coordinator context has xMin/xMax/yMin/yMax set

### "No stream initialized"
- Call `initPlotStream()` before `getStreamLayout()`
- Ensure WASM renderer has stream_state populated

### Zoom not working
- Check InteractionManager zone detection
- Verify Shift key modifier
- Check browser console for handler errors
- Ensure LayoutManager is initialized

### Chrome layers not rendering
- Check ViewStateLayer completed successfully
- Verify ChromeLayer dependencies met
- Check GPU setLayer() calls in browser DevTools

### Data layer stuck
- Check if chrome layer dependencies are complete
- Verify WASM loadDataChunk() not throwing errors
- Check generation counter hasn't been incremented (cancellation)

---

## Debug Tips

### Enable Verbose Logging

```javascript
// In render_coordinator.js, add to each layer's render():
console.log(`[${this.name}] Starting render`, ctx);
console.log(`[${this.name}] Dependencies:`, this.dependencies);
console.log(`[${this.name}] Context keys:`, Object.keys(ctx));
```

### Check Layer States

```javascript
const coordinator = ggrsV3._gpuInstances.get('plot-container').coordinator;
for (const [name, layer] of coordinator.layers) {
    console.log(`${name}: ${layer.state} (priority ${layer.priority})`);
}
```

### Inspect InteractionManager State

```javascript
const manager = ggrsV3._gpuInstances.get('plot-container').interactionManager;
console.log('State:', manager.state);
console.log('Handler:', manager.handlerType);
console.log('Dragging:', manager.isDragging);
```

### WASM Memory Inspection

```javascript
const renderer = ggrsV3._gpuInstances.get('plot-container').renderer;
const layoutState = renderer.getLayoutState();
console.log('LayoutState:', JSON.parse(layoutState));
```

---

## Performance Tips

1. **Minimize context updates** - Only call updateCoordinatorContext when metadata changes
2. **Use layer invalidation** - Don't invalidate all layers when only chrome needs updating
3. **Batch data streaming** - 15K chunk size is optimal for most cases
4. **Reuse GPU instances** - Don't recreate GPU for same container
5. **Cancel stale renders** - Use generation counter pattern

---

## API Reference Links

- Full V3 implementation: `/docs/v3-implementation-complete.md`
- Zoom architecture: `/docs/zoom-architecture.md`
- WASM API reference: `/home/thiago/workspaces/tercen/main/ggrs/docs/WASM_API_REFERENCE.md`
