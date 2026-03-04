# Issues for Later

## GGRS Chrome Format Inconsistencies (2026-03-02)

**Problem**: WASM chrome elements use inconsistent field names and color formats, requiring messy conditional logic in JS.

**Current state:**
```javascript
// Different element types use different field names:
const rects = elements.map(elem => ({
  color: this._parseColor(elem.fill || elem.color),  // Backgrounds use 'fill', lines use 'color'
}));

// Parser accepts 3 different color formats:
function _parseColor(str) {
  if (str.startsWith('#')) { ... }      // hex: #RRGGBB or #RRGGBBAA
  if (str.startsWith('rgba(')) { ... }  // CSS: rgba(r, g, b, a)
  if (str.startsWith('rgb(')) { ... }   // CSS: rgb(r, g, b)
}
```

**What needs to change in ggrs-core:**

1. **Standardize color field name**
   - All chrome elements should use `color` (not `fill` for some, `color` for others)
   - Or create a unified `ChromeElement` struct with consistent fields

2. **Standardize color format**
   - Pick ONE format: `#RRGGBB` (recommended - compact, standard)
   - Convert all color serialization to use this format consistently
   - Alternative: Use RGB array `[r, g, b, a]` to skip parsing entirely

3. **Files to investigate:**
   - Chrome serialization code in `ggrs-core` (where JSON is generated)
   - Look for structs like `Background`, `Line`, `Border` in chrome-related modules
   - Find color-to-string conversion code

**Benefits:**
- Simpler JS code (no `elem.fill || elem.color` fallback)
- Stricter validation (can fail loudly on unexpected formats)
- Better type safety
- Easier to maintain

**Current workaround:**
- JS handles both field names: `elem.fill || elem.color`
- JS parser accepts all 3 color formats (hex, rgb, rgba)

**Priority:** Medium - workaround exists, but cleaning this up would improve code quality
