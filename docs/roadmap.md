# Canister Roadmap

## Media Backends

Canister aggregates media from multiple sources into a single library. Each backend implements a common interface: browse, search, get metadata, get file stream. Transcoding to HLS happens in Canister regardless of source.

| Backend | Status | Notes |
|---------|--------|-------|
| Local filesystem | Done | Direct filesystem access |
| WebDAV | Done | Read-write capable |
| S3-compatible | Planned | AWS S3, MinIO, Backblaze B2, Wasabi |
| Jellyfin (as source) | Planned | Browse and stream from existing Jellyfin servers |
| Plex (as source) | Planned | REST API with `X-Plex-Token` auth |

## Jellyfin API Compatibility

Implement enough of the Jellyfin REST API that existing Jellyfin clients can connect to Canister as if it were a Jellyfin server. This is the primary strategy for getting Canister content onto TVs, phones, and other devices without building native apps for every platform.

### Why Jellyfin API (not DLNA)

- Standard REST over HTTP — no multicast, no SOAP/XML, no special Docker networking
- Works through standard Docker port mapping
- Infuse, Jellyfin mobile apps, Android TV, Roku, Kodi plugins, and some Samsung/LG TV apps all speak Jellyfin
- Richer experience — metadata, artwork, collections, watch progress, search

### Core Endpoints

- **Auth:** `/Users/AuthenticateByName`
- **Library browsing:** `/Items`, `/Users/{id}/Items`
- **Item details:** `/Items/{id}`
- **Images:** `/Items/{id}/Images`
- **Playback:** `/Items/{id}/PlaybackInfo` — returns HLS `.m3u8` URLs
- **Search:** `/Items?searchTerm=...`
- **Watch status:** `/Users/{id}/PlayedItems/{id}`

Starting with the minimum set for Infuse to work, then expanding based on what other clients need.

## Client Support

With the Jellyfin API compatibility layer, existing Jellyfin clients work with Canister out of the box:

- **Infuse** (iOS, tvOS, macOS)
- **Jellyfin mobile apps** (iOS, Android)
- **Jellyfin for Android TV**
- **Jellyfin for Roku**
- **Kodi** (via Jellyfin plugin)
- **Select Samsung/LG TV apps**

## Bonjour / mDNS Discovery

Zero-config discovery of the Canister server on the local network. The server advertises itself via mDNS so clients (including the tvOS app) can find it automatically without manual URL entry.

Uses the `dnssd` gem in Rails and Avahi in Docker. Requires `network_mode: host` for Docker containers (mDNS needs multicast). Manual URL entry is the fallback for networks that can't do host mode.

## tvOS App

Native Apple TV app using TVML/TVMLKit — a lightweight Swift shell (~50 lines) with server-hosted JavaScript and TVML templates. The native player handles HLS playback with scrubbing, trick play, and subtitle support.

- Discovers Canister via Bonjour, with manual URL entry as fallback
- Full tvOS look and feel using native TVML templates
- Hardware audio decoding (AC3, E-AC3, DTS)
- Distributed as a paid app to support the open source project

## MCP Endpoint

Expose an MCP endpoint (`/mcp`) using Streamable HTTP transport so LLMs can manage the Canister library. Claude Code, Claude Desktop, or any MCP-compatible client can connect and handle renaming, tagging, and organising media.

### Tools

- `list_videos` / `search_library` — browse and search
- `get_video_details` / `get_thumbnail` — metadata and visual content
- `rename_video` — rename files to a consistent scheme
- `add_tags` / `remove_tags` / `list_tags` — taxonomy management
- `create_collection` — group videos

Bearer token auth via `Authorization` header. API keys generated in Canister's settings.

## Phase Summary

| Phase | What | Effort |
|-------|------|--------|
| 1a | S3 backend | Low |
| 1b | Jellyfin API compatibility layer | Medium |
| 1c | Jellyfin as a backend source | Low |
| 1d | Plex as a backend source | Medium |
| 2 | Bonjour / mDNS discovery | Low |
| 3 | TVML tvOS app | Medium |
| 4 | MCP endpoint | Low-Medium |
