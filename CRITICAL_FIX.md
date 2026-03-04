# CRITICAL BUG FIX - 2026-03-02

## The Root Cause

**WGSL Shader Compilation Failure**

The shaders used `layout` as a uniform variable name:
```wgsl
@group(0) @binding(0) var<uniform> layout: LayoutUniforms;  // ❌ BROKEN!
```

**Problem**: `layout` is a **reserved keyword in WGSL**!

This caused:
1. Shader compilation to fail with error
2. Invalid render pipeline created
3. All draw calls silently fail
4. Canvas stays blank white

## The Fix

Renamed the uniform variable from `layout` to `u_layout`:

```wgsl
@group(0) @binding(0) var<uniform> u_layout: LayoutUniforms;  // ✅ FIXED!
```

Updated all shader references:
- `layout.canvas_size` → `u_layout.canvas_size`
- `layout.scroll_offset` → `u_layout.scroll_offset`
- `layout.x_range` → `u_layout.x_range`
- etc.

## Files Fixed

1. `apps/step_viewer/web/ggrs/ggrs_gpu_v3.js`
   - RECT_SHADER_V3 (lines 1-60)
   - POINT_SHADER_V3 (lines 62-150)

2. `apps/orchestrator/web/step_viewer/ggrs/ggrs_gpu_v3.js` (copied)

## Why This Was Hard to Find

1. The error only appears in browser console, not in test output
2. The render logs show "✓ Data points drawn" but the GPU command is invalid
3. Everything else works perfectly (initialization, buffers, layout state)
4. Only visible when checking WebGPU validation errors

## Test Now

Refresh `test_v3_render.html` - you should see:
- 🔴 RED background
- 🟢 GREEN grid lines
- 🔵 BLUE dots

## Other Fixes This Session

1. **MessageRouter** - Fixed dartify() cast issue for orchestrator
2. **Canvas positioning** - Added position: absolute + z-index
3. **Uniform buffer** - Added syncLayoutState() call in test

But this shader bug was **THE** blocker for all rendering.
