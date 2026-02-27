# Dark Mode Implementation Plan

Adds automatic dark mode that follows the browser/OS `prefers-color-scheme` setting.
No toggle, no JavaScript, no cookies — pure CSS media query.

---

## How it works

Tailwind v4 ships with `dark:` variants that map to `@media (prefers-color-scheme: dark)` by default. No configuration is required — `dark:` utilities already work once you have `@import "tailwindcss"`.

The work is entirely additive: every existing light-mode utility stays in place, and a paired `dark:` sibling is added beside it.

---

## Color mapping

Every light color used in the app has a dark equivalent:

| Light (existing)        | Dark (to add)                    | Role                    |
|-------------------------|----------------------------------|-------------------------|
| `bg-white`              | `dark:bg-gray-900`               | Page / card background  |
| `bg-gray-50`            | `dark:bg-gray-800`               | Subtle backgrounds      |
| `bg-gray-100`           | `dark:bg-gray-700`               | Hover / alt rows        |
| `border-gray-100`       | `dark:border-gray-700`           | Dividers (light)        |
| `border-gray-200`       | `dark:border-gray-700`           | Borders                 |
| `border-gray-300`       | `dark:border-gray-600`           | Form borders            |
| `text-gray-900`         | `dark:text-gray-100`             | Primary text            |
| `text-gray-700`         | `dark:text-gray-300`             | Secondary text          |
| `text-gray-600`         | `dark:text-gray-400`             | Muted text              |
| `text-gray-500`         | `dark:text-gray-400`             | Placeholder / metadata  |
| `bg-indigo-50`          | `dark:bg-indigo-900/30`          | Accent badge background |
| `text-indigo-700`       | `dark:text-indigo-300`           | Accent badge text       |
| `text-indigo-600`       | `dark:text-indigo-400`           | Links / active nav      |
| `hover:bg-indigo-50`    | `dark:hover:bg-indigo-900/20`    | Hover state             |
| `bg-blue-50`            | `dark:bg-blue-900/30`            | Flash info background   |
| `text-blue-800`         | `dark:text-blue-200`             | Flash info text         |
| `border-blue-400`       | `dark:border-blue-600`           | Flash info border       |
| `ring-indigo-500`       | `dark:ring-indigo-400`           | Focus ring              |

`text-amber-400` (star ratings) and `bg-black/70` (duration badge overlay) look fine in both modes — no change needed.

---

## Files to update

### 1. `app/assets/tailwind/application.css`

No functional changes required (dark mode is on by default in v4).

Optional: add a `@layer base` rule to prevent a white flash on dark-preference loads:

```css
@import "tailwindcss";

@layer base {
  html {
    font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }

  /* Prevent white flash before first paint on dark-preference browsers */
  html {
    color-scheme: light dark;
  }
}
```

The `color-scheme: light dark` declaration also tells the browser to style native form controls (scrollbars, `<select>`, `<input>`, etc.) in dark mode automatically.

---

### 2. `app/views/layouts/application.html.erb`

**Nav bar** (`bg-white border-b border-gray-200 sticky top-0`):
```
dark:bg-gray-900 dark:border-gray-700
```

**Nav links** (`text-gray-700`, `text-indigo-600`, `hover:text-gray-900`):
```
dark:text-gray-300 dark:text-indigo-400 dark:hover:text-gray-100
```

**Flash messages** (blue-50 background):
```
dark:bg-blue-900/30 dark:border-blue-600 dark:text-blue-200
```

**Mini player bar** (`bg-white border-t border-gray-200`):
```
dark:bg-gray-900 dark:border-gray-700
```

**Page body** — add to `<body>`:
```
bg-white dark:bg-gray-900 text-gray-900 dark:text-gray-100
```

---

### 3. `app/views/shared/_scene_card.html.erb`

**Card wrapper** (`bg-white rounded-lg border border-gray-200 shadow-sm`):
```
dark:bg-gray-800 dark:border-gray-700
```

**Title text** (`text-gray-900`):
```
dark:text-gray-100
```

**Metadata text** (`text-gray-500`, `text-gray-600`):
```
dark:text-gray-400
```

**Studio badge** (`bg-indigo-50 text-indigo-700`):
```
dark:bg-indigo-900/30 dark:text-indigo-300
```

The duration overlay (`bg-black/70 text-white`) and thumbnail placeholder work fine in dark mode already.

---

### 4. `app/views/shared/_person_card.html.erb`

Same pattern as scene card:
- Card: `dark:bg-gray-800 dark:border-gray-700`
- Name: `dark:text-gray-100`
- Count/metadata: `dark:text-gray-400`

---

### 5. `app/views/shared/_filter_sidebar.html.erb`

**Section headings** (`text-gray-700 font-medium`):
```
dark:text-gray-300
```

**Text inputs / selects** (`border border-gray-300 bg-white text-gray-900`):
```
dark:border-gray-600 dark:bg-gray-800 dark:text-gray-100
```

**Focus ring** (`focus:ring-indigo-500 focus:border-indigo-500`):
```
dark:focus:ring-indigo-400 dark:focus:border-indigo-400
```

**Checkbox labels** (`text-gray-700`):
```
dark:text-gray-300
```

**Scrollable lists** (`border border-gray-200 rounded bg-white`):
```
dark:border-gray-700 dark:bg-gray-800
```

**Sort/direction buttons** (`text-gray-600 hover:bg-gray-100`):
```
dark:text-gray-400 dark:hover:bg-gray-700
```

---

### 6. `app/views/scenes/index.html.erb`

**List view rows** (`divide-y divide-gray-100`):
```
dark:divide-gray-700
```

**List row hover** (`hover:bg-gray-50`):
```
dark:hover:bg-gray-800
```

**Column headers / labels** (`text-gray-500`):
```
dark:text-gray-400
```

**Pagination links** — apply same text/border dark variants.

---

### 7. `app/views/scenes/show.html.erb`

**Stats grid** (`bg-gray-50 rounded-lg`):
```
dark:bg-gray-800
```

**Stat labels** (`text-gray-500`):
```
dark:text-gray-400
```

**Stat values** (`text-gray-900`):
```
dark:text-gray-100
```

**Sidebar section headings** and metadata rows: same gray mapping.

**Marker pills / badges**: apply same indigo/gray dark pairs as cards.

**Video.js player**: The default Video.js skin is already dark — no changes needed. The surrounding container background should match: `dark:bg-gray-900`.

---

### 8. `app/views/people/show.html.erb`, `app/views/studios/show.html.erb`

Apply same patterns: white backgrounds → `dark:bg-gray-900`/`dark:bg-gray-800`, gray text → corresponding dark equivalents, borders → `dark:border-gray-700`.

---

### 9. `app/views/tags/index.html.erb`

Tag chips (likely `bg-gray-100 text-gray-700`):
```
dark:bg-gray-700 dark:text-gray-200
```

---

## Stimulus controller consideration

`view_mode_controller.js` persists the view mode in `localStorage` — no dark mode logic needed there.

`scene_card_controller.js` (hover preview) is DOM-manipulation only — no changes needed.

No Stimulus controller is required for browser-preference dark mode.

---

## Implementation order

1. `app/assets/tailwind/application.css` — add `color-scheme: light dark` (5 min)
2. `app/views/layouts/application.html.erb` — body, nav, flash, mini-player (15 min)
3. `app/views/shared/_scene_card.html.erb` — highest-frequency component (15 min)
4. `app/views/shared/_filter_sidebar.html.erb` — forms need care (20 min)
5. `app/views/scenes/index.html.erb` — list/grid/wall wrappers (15 min)
6. `app/views/scenes/show.html.erb` — stats, sidebar, metadata (20 min)
7. Remaining index/show views: people, studios, tags (20 min)
8. Smoke-test in Chrome DevTools → Rendering → Emulate CSS prefers-color-scheme: dark

Total estimate: ~2 hours of focused editing.

---

## Testing

In Chrome DevTools:
1. Open DevTools → More tools → Rendering
2. Set "Emulate CSS media feature prefers-color-scheme" to `dark`
3. Check each page and all three view modes (grid / list / wall)

In macOS System Preferences → Appearance: toggle between Light and Dark to verify live switching.

Key things to check:
- No pure-white elements survive in dark mode
- Form inputs have visible borders and legible text
- Focus rings are visible
- The sticky nav and fixed mini-player darken correctly
- Scrollable filter lists (overflow containers) are dark inside
- Text contrast meets WCAG AA on all backgrounds
