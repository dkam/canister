# Canister Roadmap

## Near-term (Frontend)

### Solid Trifecta Migration
- Replace Redis with `solid_cache`, `solid_queue`, `solid_cable` (gems already in Gemfile)
- Configure `config/database.yml` with separate SQLite databases for each

### Ruby 4.0.1 Upgrade
- Currently on Ruby 3.4.7 — run `rubyup` skill before upgrading

### Fix `rubyzip` API
- Uses pre-v3 API — update when bumping to `~> 2.3+`

### UX Enhancements
- Mobile nav (hamburger / bottom tab bar)
- Dark mode toggle
- Keyboard shortcuts (Space, ←/→, F, M)
- Gallery browser for scenes with attached galleries
- Turbo Frames for filter sidebar (partial updates instead of full Turbo Drive)

### Watch History
- Persist resume position to DB (currently sessionStorage only)

### Scene Queue / Playlist
- Queue with autoplay, shuffle mode

---

# Roadmap (Prior)

## Multi-User Support & Authentication

### Default Rails Auth (No Devise)
- [ ] Create `User` model with authentication
  - email, password_digest (using has_secure_password)
  - timestamps
- [ ] Add password hashing (bcrypt gem)
- [ ] Implement session-based authentication
  - Sessions table
  - Login/logout actions
  - Session management middleware (since this is API-only, we'll need to add back session/cookie middleware)
- [ ] Add authentication helpers to ApplicationController
  - `current_user`
  - `authenticate_user!`
  - `user_signed_in?`

### OIDC (OpenID Connect) Authentication
- [ ] Add `omniauth-openid_connect` gem
- [ ] Configure OIDC provider
  - Client ID/Secret in application.yml
  - Discovery URL
  - Scopes
- [ ] Implement OIDC authentication flow
  - Callback controller
  - User lookup/create on authentication
  - Session management for OIDC users
- [ ] Support both local password and OIDC auth
- [ ] Add OIDC provider configuration options

## Video Markers

### Configurable Length Markers
- [ ] Extend `SceneMarker` model with length/duration
  - Add `duration` field (in seconds)
  - Markers now represent a segment from `seconds` to `seconds + duration`
  - Backward compatible: existing markers default to 0 duration (point markers)
- [ ] Update marker preview generation
  - Generate preview clip for the full duration (not just a point)
  - Configurable preview length limits (e.g., max 30s)
  - Use same FFmpeg pipeline as scene previews
- [ ] Update marker API
  - Query for markers by duration range
  - Filter for point markers (duration = 0) vs segment markers
  - Return start/end times for segment markers
- [ ] UI/UX considerations
  - Display marker segments on timeline
  - Show duration in marker list
  - Allow trimming/resizing segments

### Video Snippets
- [ ] Create `Snippet` model
  - scene_id (references scenes)
  - user_id (references users, creator)
  - title
  - start_time (seconds)
  - end_time (seconds)
  - duration (seconds, calculated)
  - checksum (MD5 of source scene + start/end times)
  - file_path (where the generated clip is stored)
  - status (pending, processing, ready, failed)
  - created_at, updated_at
  - expires_at (optional, for auto-deletion)
- [ ] Snippet generation pipeline
  - FFmpeg job to extract segment from source video
  - Use same encoding settings as scene transcoding
  - Support different quality presets (high, medium, low)
  - Generate thumbnail for snippet
  - Store in dedicated snippets directory
- [ ] Snippet API
  - `POST /scenes/:id/snippets` - create snippet from scene
  - `GET /snippets` - list snippets (scoped by user)
  - `GET /snippets/:id` - get snippet details
  - `GET /snippets/:id/stream` - stream snippet
  - `GET /snippets/:id/download` - download snippet
  - `DELETE /snippets/:id` - delete snippet
- [ ] Snippet from markers
  - Create snippet directly from existing scene markers
  - Use marker start time and duration
  - Batch create multiple snippets from markers
- [ ] Snippet management
  - List user's snippets
  - View snippet status
  - Re-generate failed snippets
  - Set expiration time for temporary snippets
- [ ] Storage and cleanup
  - Dedicated snippets cache directory
  - Background job to delete expired snippets
  - Track storage usage per user
  - Optional: soft delete before permanent deletion

### Snippet Sharing
- [ ] Share snippets via share links
  - Reuse existing Share model, add polymorphic association
  - Share can reference either Scene or Snippet
  - Same TTL/IP/use limit features
- [ ] Public snippet gallery (optional)
  - Allow users to make snippets publicly viewable
  - Require moderation/approval
  - Searchable by tags, title, creator

## Video Sharing

### Share Link System
- [ ] Create `Share` model
  - scene_id (references scenes)
  - user_id (references users, creator)
  - token (unique string, index)
  - expires_at (datetime)
  - max_uses (integer, optional, null = unlimited)
  - use_count (integer, default 0)
  - allowed_ips (text/array, IP whitelist, optional)
  - allow_download (boolean, default false)
  - created_at, updated_at
- [ ] Add share routes/controllers
  - `GET /shares/:token` - access shared content
  - `POST /scenes/:id/share` - create share link
  - `GET /scenes/:id/shares` - list shares for a scene
  - `DELETE /shares/:id` - revoke/delete share

### Share Link Features
- [ ] Time-to-live (TTL) configuration
  - Configurable default TTL (hours/days)
  - Custom expiration per share
  - Expired share cleanup job
- [ ] IP-based access limiting
  - Track IPs accessing shares
  - Enforce max allowed IPs if configured
  - Allow wildcard IP ranges (e.g., 192.168.1.*)
- [ ] Use tracking
  - Increment use_count on each access
  - Respect max_uses limit
  - Disable share when limit reached
- [ ] Download option
  - If `allow_download` = true, provide direct download endpoint
  - If false, streaming only
  - Rate limiting for downloads

### Share Management
- [ ] User can list their shares
- [ ] User can revoke/delete their shares
- [ ] View share statistics (uses, expiration, last accessed)
- [ ] Admin ability to view/delete any share

### Security
- [ ] Secure token generation (SecureRandom.urlsafe_base64)
  - Minimum 32 characters
- [ ] Share access logging
  - IP, timestamp, user agent
- [ ] Rate limiting on share endpoints
- [ ] Optional password protection for share links
- [ ] CAPTCHA option for public-facing shares

## Implementation Order

### Phase 1: Authentication Foundation
1. User model + bcrypt
2. Session/cookie middleware (add back to API-only mode)
3. Basic login/logout
4. Authentication helpers

### Phase 2: OIDC Integration
1. OmniAuth setup
2. OIDC provider configuration
3. Authentication flow
4. User provisioning from OIDC

### Phase 3: Multi-User Data Isolation
1. Add user associations to existing models (scenes, galleries, etc.)
2. Scope queries by current_user
3. Update all controllers to enforce ownership
4. Seed initial admin user

### Phase 4: Share System
1. Share model and migrations
2. Share creation routes
3. Share access logic
4. IP tracking and limits
5. Download endpoint

### Phase 5: Share Features Polish
1. TTL configuration
2. Share management UI/API
3. Statistics and logging
4. Optional password protection
5. Rate limiting

## Configuration (application.yml)

```yaml
# Authentication
auth_method: "both"  # local, oidc, or both

# OIDC Configuration
oidc_client_id: ""
oidc_client_secret: ""
oidc_discovery_url: "https://your-oidc-provider/.well-known/openid-configuration"
oidc_scopes: "openid email profile"
oidc_callback_path: "/auth/openid_connect/callback"

# Default Share Settings
default_share_ttl_hours: 24
default_share_max_uses: null  # null = unlimited
default_share_allow_download: false

# Rate Limiting
share_rate_limit_per_minute: 10
download_rate_limit_per_hour: 5
```

## Notes

- This app is API-only, so we'll need to add back session/cookie middleware for browser-based auth
- OIDC users will be auto-provisioned on first login
- Local password users can be created via CLI or initial seed
- No permission system planned - all users have same access level
- Admin user can be designated by a boolean flag on User model if needed
