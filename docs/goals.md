# Canister — Project Plan

## What Is Canister?

Canister is a self-hosted video platform that aggregates media from multiple backends and provides first-class playback everywhere. Built on StashServer (MIT licensed, Rails backend).

**Nothing else does this.** Jellyfin, Plex, and Emby all assume they own the storage layer. Kodi aggregates sources but is a local player with no web UI. Infuse is Apple-only with no server component. Canister is the missing piece: a smart frontend that doesn't care where your files live.

### Key Differentiators

- **Multi-backend aggregation** — local files, WebDAV, S3, Jellyfin servers, Plex servers, all unified in one library
- **First-class web playback** — HLS streaming in the browser, same approach as Stash
- **Jellyfin API compatibility** — existing clients (Infuse, Jellyfin apps on every platform) work out of the box
- **Native Apple TV app** — TVML-based tvOS app with deep Canister integration
- **AI-powered library management** — MCP endpoint lets LLMs handle renaming, tagging, and organising
- **Fully open source** — MIT licensed, Docker-based, designed for self-hosting

---

## 1. Media Backends

### Currently Working

- **Local files** — direct filesystem access
- **WebDAV** — remote file servers

### To Implement

**S3-compatible storage** — should be straightforward to add. Covers AWS S3, MinIO, Backblaze B2, Wasabi, and any S3-compatible provider.

**Jellyfin as a backend** — use the Jellyfin API to browse and stream from an existing Jellyfin server. The API provides both original file download and transcoded streams. Canister can either pull originals and transcode via its own HLS pipeline, or proxy Jellyfin's transcoded output. A Ruby gem for Jellyfin API access has already been built previously.

**Plex as a backend** — Plex now has official API documentation (published late 2025). Auth uses `X-Plex-Token` header. The user provides their Plex server host, port, and token in Canister's settings. Canister browses the library via the REST API (JSON or XML responses) and pulls original files for its own transcoding. Notes:

- Plex auth routes through `plex.tv` even for local access — self-hosters should be aware
- Hardware transcoding on Plex requires Plex Pass, but irrelevant since Canister does its own transcoding
- Plex has moved to JWT auth with short-lived tokens — for simplicity, support the classic `X-Plex-Token` initially

### Architecture

Each backend implements a common interface: browse, search, get metadata, get original file stream. The Canister library unifies content from all backends into a single browsable collection. Transcoding to HLS happens in Canister regardless of source.

---

## 2. Jellyfin API Compatibility Layer

**Goal:** Implement enough of the Jellyfin API that existing Jellyfin clients can connect to Canister as if it were a Jellyfin server. This is the primary strategy for getting Canister content onto TVs, phones, and other devices without building native apps for every platform.

### Why This Over DLNA

- It's just REST over HTTP — no multicast, no SOAP/XML, no SSDP, no special Docker networking
- Works through standard Docker port mapping with zero fuss for self-hosters
- Infuse, Jellyfin mobile apps, Android TV, Roku, Kodi plugins, and some Samsung/LG TV apps all speak Jellyfin
- Richer experience than DLNA — metadata, artwork, collections, watch progress, search

### Endpoints to Implement

Core subset that clients actually use:

- **Auth:** `/Users/AuthenticateByName` — login flow
- **Library browsing:** `/Items`, `/Users/{id}/Items` — list and filter content
- **Item details:** `/Items/{id}` — full metadata for a single item
- **Images:** `/Items/{id}/Images` — thumbnails, artwork, backdrops
- **Playback:** `/Items/{id}/PlaybackInfo` — tells the client what streams are available, returns HLS `.m3u8` URLs
- **Search:** `/Items?searchTerm=...` — library search
- **Watch status:** `/Users/{id}/PlayedItems/{id}` — mark watched/unwatched, resume position

Start with the minimum for Infuse to work, then expand based on what other clients need.

---

## 3. Bonjour / mDNS Service Discovery

**Goal:** Zero-config discovery of the Canister server on the local network.

### Rails Implementation

```ruby
# config/initializers/bonjour.rb
require 'dnssd'

Thread.new do
  DNSSD.register!(
    "Canister",
    "_canister._tcp",
    nil,    # domain - nil for default
    3000,   # port
    DNSSD::TextRecord.new("version" => "1.0", "path" => "/api")
  )
  Rails.logger.info "Bonjour: registered Canister on _canister._tcp"
end
```

### Dockerfile Additions

```dockerfile
RUN apt-get update && apt-get install -y \
    avahi-daemon \
    libavahi-compat-libdnssd-dev
```

Start `avahi-daemon --daemonize --no-chroot` in the entrypoint before Rails.

### Docker Networking

mDNS requires multicast, which doesn't work with standard Docker port mapping. The container needs `network_mode: host`:

```yaml
services:
  canister:
    image: canister
    network_mode: host
    environment:
      - PORT=3000
```

Document for self-hosters. Provide manual URL entry fallback for networks that can't do host mode.

---

## 4. TVML / tvOS App

**Goal:** Native Apple TV app providing a polished, Canister-specific experience. Distributed as a paid app to support the open source project.

### Architecture

- Apple TV runs a lightweight native app shell (TVMLKit JavaScript runtime)
- On boot, the app discovers the Canister server via Bonjour (mDNS), with manual URL entry as fallback
- The JS entry point fetches data from Canister's API and constructs TVML template documents
- Apple TV renders these natively with full tvOS look and feel

### Discovery Flow

1. **Primary:** Bonjour autodiscovery using `NetServiceBrowser` in Swift (~20 lines). App boots → scans for `_canister._tcp` → finds server → loads JS entry point.
2. **Fallback:** Manual URL entry via `textFieldTemplate`, or pairing code displayed on TV that user enters at `canister.local/pair/ABCD`.

### TVML Templates

- `catalogTemplate` — browse library with categories
- `stackTemplate` / `gridTemplate` — list videos with thumbnails
- `productTemplate` — video detail page (description, metadata, play button)
- `compilationTemplate` — series or collections

### Playback

The TVML `Player` JS object takes HLS `.m3u8` URLs directly. Native playback with scrubbing, trick play, subtitle support, and standard tvOS player chrome — all for free.

### Audio Codec Support

The native TVMLKit player uses AVFoundation, which hardware-decodes on Apple TV silicon:

- Dolby Digital (AC3)
- Dolby Digital Plus (E-AC3)
- Dolby Atmos (E-AC3-JOC)
- DTS / DTS-HD

No app-side audio code needed. On the Canister transcoding side:

- Use `-c:a copy` in FFmpeg for passthrough when source already has AC3/E-AC3/DTS
- Transcode to E-AC3 for MPEG-TS segments (TS doesn't support DTS; fMP4 does)
- Set correct `CODECS` in `#EXT-X-STREAM-INF` (`ac-3`, `ec-3`, `dtsc`)

### Native App Shell

Minimal Swift — ~50 lines bootstrapping a `TVApplicationController` pointed at the server's JS entry point. All UI logic lives in server-hosted JavaScript and TVML templates.

### Distribution & Revenue Model

- **Positioning:** "Support this free open source project by buying the tvOS app"
- **Pricing:** ~$5 AUD/year or ~$15–20 AUD lifetime
- Apple takes 30% → ~$3.50 net per annual sub
- Requires Apple Developer Program ($149 AUD/year) → need ~43 subscribers to cover the fee
- **Value over Infuse/VLC:** deep Canister integration — custom taxonomy browsing, watch history synced with web UI, continue watching, curated collections, search across all backends

---

## 5. MCP Endpoint

**Goal:** Let LLMs manage the Canister library — renaming, tagging, categorising media via Claude Code, Claude Desktop, or any MCP-compatible client.

### Protocol

MCP uses **Streamable HTTP** transport — a single HTTP endpoint (`/mcp`) accepting JSON-RPC POST requests. No special daemon, CLI tool, or sidecar needed.

### Auth

Bearer token in the `Authorization` header. Generate API keys in Canister's settings UI.

### Client Configuration

```json
{
  "mcpServers": {
    "canister": {
      "type": "streamable-http",
      "url": "http://192.168.1.50:3000/mcp",
      "headers": {
        "Authorization": "Bearer your-canister-api-key"
      }
    }
  }
}
```

### Tool Definitions

- `list_videos` — browse/search the library
- `get_video_details` — metadata, tags, file info
- `rename_video` — rename files to consistent scheme
- `add_tags` / `remove_tags` — manage tags
- `list_tags` — lets the LLM know existing taxonomy before inventing new tag names
- `create_collection` — group videos
- `search_library` — full-text / filtered search
- `get_thumbnail` — let vision models see content for auto-tagging

### Rails Implementation

Single controller action parsing JSON-RPC, dispatching based on method name (`tools/list`, `tools/call`, `initialize`), returning JSON-RPC responses. Consider the `mcp` Ruby gem or roll your own — the protocol is straightforward.

**Important:** Include a `list_tags` / `get_schema` tool so the LLM knows the existing taxonomy. Without this, it will invent its own tag names and you'll end up with "Action", "action", and "Action Movies" as separate tags.

---

## 6. Use Cases & Workflows

### The Aggregator

User has media spread across a NAS (local files), a Jellyfin server, and an S3 bucket. Canister presents it all as one library. They browse on the web, watch on Apple TV via the tvOS app or Infuse, and use Claude to auto-tag new additions.

### The Migrator

User wants to move off Plex. They add their Plex server as a Canister backend and start using Canister's web UI immediately. Media can be gradually moved to local/S3 storage without disrupting playback.

### The Organiser

User has a large unorganised library. They point Claude at Canister via MCP: "I just added 200 files to the inbox, sort them out." Claude reads filenames, examines thumbnails, renames to a consistent scheme, tags with genres/categories, and groups into collections.

---

## Phase Summary

| Phase | What | Effort | Notes |
|-------|------|--------|-------|
| 1a | S3 backend | Low | Straightforward addition |
| 1b | Jellyfin API compatibility layer | Medium | Primary client compatibility strategy — replaces DLNA |
| 1c | Jellyfin as a backend source | Low | Ruby gem already exists |
| 1d | Plex as a backend source | Medium | Official API now documented, auth is more complex |
| 2 | Bonjour / mDNS discovery | Low | Parallel with any phase |
| 3 | TVML tvOS app | Medium | Depends on stable Canister API |
| 4 | MCP endpoint | Low–Medium | Depends on existing API endpoints |