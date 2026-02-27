# Plan: Canister Web Frontend (Tailwind + Stimulus + Turbo)

## Context

Canister is a Rails 8.1 server for media organisation. GraphQL and ActionCable were removed. This plan adds a full HTML frontend using Rails' native Turbo/Stimulus/Tailwind stack — no separate frontend app, no build step, no Node.

The UX model is **Plex-inspired**: a scene detail page with a large embedded Video.js player, `data-turbo-permanent` keeping the player alive across Turbo navigations, plus a persistent mini-player when browsing other pages.

Reference UX drawn from:
- `tmp/StashFrontend` (Angular app — layout, filter patterns)
- `tmp/stash` (React app — Video.js player, card grid, 3 view modes, sidebar filters)

---

## Implementation Status

### Phase 1: Infrastructure ✅

- Removed `config.api_only = true` from `config/application.rb`
- `ApplicationController` → `ActionController::Base`, added `Pagy::Backend`, `protect_from_forgery`
- **Gems added**: `propshaft`, `tailwindcss-rails`, `turbo-rails`, `stimulus-rails`, `importmap-rails`, `pagy`
- **kaminari** → replaced by **pagy**
- `config/importmap.rb` — pins Turbo, Stimulus, application, Video.js (CDN)
- `app/assets/stylesheets/application.css` — `@import "tailwindcss"` (Tailwind v4, no config file)
- `app/javascript/application.js` — bootstraps Turbo + Stimulus
- `app/javascript/controllers/` — Stimulus controller registry
- `app/helpers/application_helper.rb` — `nav_link_class`, `rating_stars`, `format_duration`, `format_filesize`
- `config/initializers/kaminari_config.rb` → repurposed as pagy config (loads `pagy/extras/tailwind`)

### Phase 2: Routes, Layout, Controllers ✅

**`config/routes.rb`** — restructured:
- `root → scenes#index`
- `resources :scenes, only: [:index, :show]` with member routes for streaming endpoints
- `resources :performers, only: [:index, :show]`
- `resources :studios, only: [:index, :show]`
- `resources :tags, only: [:index]`

**`ScenesController`**:
- `index` — paginated, filterable (rating, resolution, studio_id, tags, performers), sortable
- `show` — loads scene + markers + performers
- Bug fixed: `params[:format] == :jpg` → `params[:format] == "jpg"` (line ~68)

**`PerformersController`**:
- `index` — paginated, searchable, favorites filter
- `show` — performer detail + associated scenes

**`StudiosController`**:
- `index` / `show` — paginated, searchable

**`TagsController`**:
- `index` — all tags with scene count (single LEFT JOIN query)

### Phase 3: Views & Stimulus ✅

**Layout** (`app/views/layouts/application.html.erb`):
- Light theme (white nav, gray-50 body)
- Sticky top nav with active link highlighting
- `#mini-player` with `data-turbo-permanent` — persistent bottom bar

**Shared Partials**:
- `_scene_card` — thumbnail, duration, studio badge, performer names, rating
- `_performer_card` — portrait photo, name, scene count
- `_filter_sidebar` — search, sort, rating, resolution, studio, performers, tags
- `_mini_player` — "Now Playing" bar with title + resume link + dismiss

**Scene Views**:
- `index` — 3 view modes (Grid/List/Wall), Turbo Frame `#scenes`, filter sidebar, pagination
- `show` — Video.js player (permanent), metadata panel, performers grid, markers list, tags

**Performer Views**: `index` (card grid + search), `show` (profile + scenes)

**Studio Views**: `index` (card grid + search), `show` (header + scenes)

**Tags View**: `index` — alphabetical grouping with scene count badges, links to filtered scene list

**Stimulus Controllers**:

| Controller | File | Purpose |
|---|---|---|
| `player` | `player_controller.js` | Video.js init, resume position, scene-to-scene updates, mini-player handoff |
| `mini-player` | `mini_player_controller.js` | Persistent bottom bar, show/hide on `turbo:load` |
| `scene-card` | `scene_card_controller.js` | Hover preview video (300ms delay) |
| `filter` | `filter_controller.js` | Form submit + debounce for text search |
| `view-mode` | `view_mode_controller.js` | Grid/List/Wall toggle with localStorage persistence |
| `search` | `search_controller.js` | Standalone debounced search input |
| `markers` | `markers_controller.js` | Scene marker list → seek Video.js player |

---

## Key Design Decisions

- **Light colour scheme** — white/gray-50 surfaces, indigo accents
- **Pagy** for pagination with Tailwind extra (`pagy/extras/tailwind`)
- **Tailwind v4** — CSS-first, no `tailwind.config.js` required; `@import "tailwindcss"` in CSS
- **Turbo Drive** + `data-turbo-permanent` for player/mini-player persistence
- **No video in mini player** — mini player is a "Now Playing" resume bar (simpler, no duplicate video element)
- **Video.js 8.x** loaded via jsDelivr CDN, pinned in importmap

---

## Verification Checklist

1. `bundle install` — gems install cleanly
2. `rails tailwindcss:build` — CSS generates
3. `rails s` → `http://localhost:3000` — scene list loads
4. Scene card hover → preview video plays
5. Click scene → detail page + Video.js player
6. Navigate to Performers → mini-player appears
7. Filter sidebar → Turbo updates scene list in-place
8. View mode toggle → persists in localStorage
9. Scene markers → click → video seeks
