# NGINX Removal Plan

## Overview
Remove NGINX and Passenger completely, use Puma directly with vanilla Rails defaults. SSL/TLS will be handled upstream at deployment time (via Caddy, Kamal, Traefik, etc.).

## Why This Approach

Your requirements align perfectly with Rails defaults:
- ✅ **No SSL needed in app** - handled upstream
- ✅ **Performance "good enough"** - Rails `send_file` is sufficient for video streaming
- ✅ **Frontend "nice to have"** - Rails public folder works fine
- ✅ **Ruby ecosystem preference** - no external dependencies
- ✅ **Mixed deployment** - simpler stack works anywhere

## What NGINX Currently Does

Based on the existing config, NGINX handles:

1. **X-Accel-Redirect for efficient file serving**
   - Maps internal paths to filesystem
   - Used for video streaming to avoid Ruby process overhead
   - ActiveStorage can use this but doesn't require it

2. **Static file serving** (port 8008)
   - Serves old React frontend
   - SPA routing fallback to index.html

3. **SSL/TLS termination** (commented out, never used)
   - No longer needed - will be upstream

## What Replaces NGINX

| NGINX Feature | Rails/Puma Equivalent |
|--------------|---------------------|
| X-Accel-Redirect | Rails `send_file` (ActiveStorage uses this by default) |
| Static file serving | Puma serves `public/` directory directly |
| SSL/TLS | Handled upstream (Caddy, Kamal, Traefik) |
| Reverse proxy | Not needed - Puma handles HTTP directly |

---

## Phase 1: Update Dockerfile

### 1.1 Switch from Passenger Base Image

**Current:**
```dockerfile
FROM phusion/passenger-full:0.9.30
```

**New:**
```dockerfile
FROM ruby:3.4.7-slim
```

### 1.2 Remove Passenger/NGINX Components

**Remove these lines:**
```dockerfile
# Remove startup scripts
RUN mkdir -p /etc/my_init.d
ADD docker/setup_stash.rb /etc/my_init.d/setup_stash.rb
RUN chmod +x /etc/my_init.d/setup_stash.rb

# Use baseimage-docker's init process.
CMD ["/sbin/my_init"]
```

**Remove these lines:**
```dockerfile
# Set the newest ruby version
RUN bash -lc 'rvm --default use ruby-2.4.4'

# Fix broken bundler
RUN gem install bundler

# Expose Nginx HTTP service
EXPOSE 80 3000 4000 4001 8008

# Start Nginx / Passenger
RUN rm -f /etc/service/nginx/down
RUN rm -f /etc/service/redis/down

# Remove the default site
RUN rm /etc/nginx/sites-enabled/default

# Add nginx site and config
ADD docker/nginx.conf /etc/nginx/sites-enabled/stash.conf
ADD docker/nginx_frontend.conf /etc/nginx/sites-enabled/stash_frontend.conf
ADD docker/rails-env.conf /etc/nginx/main.d/rails-env.conf
```

### 1.3 Clean Up Dependencies

**Remove these lines (Passenger/NGINX related):**
```dockerfile
# Clean up packages that aren't needed
RUN apt-get purge -y libmagic-dev gcc g++ gcc-5 x11-common openjdk-8-jre-headless memcached \
  mysql-common openssh-sftp-server openssh-server openssh-client passenger-doc m4 git-man bison \
  && apt-get autoremove -y
```

**New simplified cleanup:**
```dockerfile
# Clean up
RUN apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
```

### 1.4 Remove Old Frontend Build

**Remove these lines (React frontend no longer needed):**
```dockerfile
# Install global node modules
RUN yarn global add gulp
RUN yarn global add @angular/cli

# ...

# Install the frontend
RUN git clone https://github.com/StashApp/StashFrontend.git
RUN cd StashFrontend && yarn install
RUN cd StashFrontend \
    && ng build --prod \
    && mv dist/* $APP_FRONTEND_HOME \
    && chown -R app:app $APP_FRONTEND_HOME
```

### 1.5 Final Dockerfile

```dockerfile
FROM ruby:3.4.7-slim

# Install system dependencies
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends \
    ffmpeg \
    imagemagick \
    nodejs \
    yarn \
    build-essential \
    git \
  && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Ruby dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Install frontend dependencies (Tailwind/Stimulus/Turbo)
COPY package.json yarn.lock ./
RUN yarn install

# Copy application code
COPY . .

# Precompile assets
RUN RAILS_ENV=production SECRET_KEY_BASE=dummy rails assets:precompile

# Expose Puma port
EXPOSE 3000

# Set environment variables
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

# Start Puma
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

---

## Phase 2: Update Docker Compose

### 2.1 Simplify docker-compose.yml

**Current:**
```yaml
version: '2'
services:
  web:
    build: .
    ports:
      - "3000:3000"
      - "4000:4000"
      - "4001:4001"
      - "8008:8008"
    env_file:
      - .env
    volumes:
      - ${STASH_DATA}:${STASH_DATA}:ro
      - ${STASH_METADATA}:${STASH_METADATA}
      - ${STASH_CACHE}:${STASH_CACHE}
      - ${STASH_DOWNLOADS}:${STASH_DOWNLOADS}
```

**New:**
```yaml
version: '3.8'
services:
  web:
    build: .
    ports:
      - "3000:3000"
    env_file:
      - .env
    volumes:
      - ${STASH_DATA}:${STASH_DATA}:ro
      - ${STASH_METADATA}:${STASH_METADATA}
      - ${STASH_CACHE}:${STASH_CACHE}
      - ${STASH_DOWNLOADS}:${STASH_DOWNLOADS}
      - ${STASH_STORAGE}:/app/storage  # ActiveStorage bind mount
    environment:
      - RAILS_ENV=${RAILS_ENV:-development}
      - RAILS_LOG_TO_STDOUT=true
      - RAILS_SERVE_STATIC_FILES=${RAILS_SERVE_STATIC_FILES:-true}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
```

**Changes:**
- ✅ Single port exposure (3000 only)
- ✅ Added ActiveStorage volume mount
- ✅ Added healthcheck
- ✅ Added environment variables
- ✅ Updated to version 3.8 format

---

## Phase 3: Update Rails Configuration

### 3.1 Remove X-Sendfile Configuration

**File:** `config/environments/production.rb`

**Remove these lines (no longer needed):**
```ruby
config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'
```

Rails will now use direct `send_file` instead of X-Accel-Redirect.

### 3.2 Update Puma Configuration

**File:** `config/puma.rb`

```ruby
# Puma configuration for production use

# Max threads (default is 5)
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Port
port ENV.fetch("PORT") { 3000 }

# Environment
environment ENV.fetch("RAILS_ENV") { "production" }

# Workers for multi-process mode
# Uncomment in production for better performance
# workers ENV.fetch("WEB_CONCURRENCY") { 2 }
# preload_app!

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Worker timeout (kill workers that hang for 60 seconds)
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "production"

# Before fork in workers
# before_fork do
#   ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
# end

# On worker boot
# on_worker_boot do
#   ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
# end
```

### 3.3 Configure Static File Serving

**File:** `config/environments/production.rb`

```ruby
# Serve static files from `public/`
config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

# Cache static assets
config.public_file_server.headers = {
  'Cache-Control' => "public, max-age=#{365.days.to_i}, immutable"
}

# Compress responses
config.assets.compress = true

# Use SHA256 fingerprinting for assets
config.assets.css_compressor = nil
config.assets.js_compressor = :terser
```

### 3.4 ActiveStorage Configuration

**File:** `config/environments/production.rb`

```ruby
# ActiveStorage - configure for direct file serving
config.active_storage.service = :local_media
config.active_storage.service_urls_expire_in = 1.year

# For ActiveStorage URL generation
config.active_storage.service_urls_configure_in = :production
```

**File:** `config/storage.yml`

```yaml
local_media:
  service: Disk
  root: <%= Rails.root.join("storage") %>

test:
  service: Disk
  root: <%= Rails.root.join("tmp/storage") %>
```

---

## Phase 4: Update Controllers

### 4.1 Remove X-Sendfile Headers

**File:** `app/controllers/application_controller.rb`

**No changes needed** - just remove any X-Sendfile related code if present.

### 4.2 Update File Serving Methods

ActiveStorage automatically handles file serving with `send_file`. No changes needed for:
- `performers_controller.rb#image`
- `studios_controller.rb#image`
- `scenes_controller.rb#stream`
- `scenes_controller.rb#screenshot`
- etc.

They will work the same way, just without X-Accel-Redirect overhead.

---

## Phase 5: Remove Unused Files

### 5.1 Delete NGINX Configuration Files

```bash
rm docker/nginx.conf
rm docker/nginx_frontend.conf
rm docker/nginx_proxy.conf
rm docker/rails-env.conf
rm docker/setup_stash.rb
```

### 5.2 Update .gitignore

**Add these lines:**
```
/storage/*
!/storage/.keep
```

**Remove these lines (if present):**
```
/home/app/frontend
```

### 5.3 Remove Frontend References

**File:** `README.md`

Remove references to StashFrontend and port 8008.

---

## Phase 6: Update .env.example

**File:** `.env.example`

```bash
# Rails Environment
RAILS_ENV=production
RAILS_MASTER_KEY=your_master_key_here

# Puma Configuration
PORT=3000
RAILS_MAX_THREADS=5
WEB_CONCURRENCY=2

# File Paths
STASH_DATA=/path/to/media
STASH_METADATA=/path/to/metadata
STASH_CACHE=/path/to/cache
STASH_DOWNLOADS=/path/to/downloads
STASH_STORAGE=/path/to/storage  # ActiveStorage

# Logging
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# Solid Queue
SOLID_QUEUE=1
```

---

## Phase 7: Deployment Considerations

### 7.1 Kamal Deployment

**File:** `config/deploy.yml` (create new file)

```yaml
service: canister

image: your-org/canister

servers:
  web:
    - 192.0.2.1
    - 192.0.2.2

proxy:
  ssl: true
  host: canister.example.com

builder:
  multiarch: false

ssh:
  user: deploy

env:
  secret:
    RAILS_MASTER_KEY:
      - KAMAL_REGISTRY_PASSWORD
```

Kamal automatically:
- Uses Caddy for SSL/TLS termination
- Proxies to your Puma server
- Handles zero-downtime deployments

### 7.2 Docker Healthcheck

Already added to docker-compose.yml (Phase 2.1). For production:

```yaml
healthcheck:
  test: ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 10s
```

---

## Phase 8: Performance Considerations

### 8.1 File Serving Performance

| Approach | Performance | Notes |
|----------|-------------|-------|
| NGINX X-Accel-Redirect | ★★★★★ | Zero-copy, minimal Ruby overhead |
| Rails `send_file` | ★★★★☆ | Copy through Ruby, but still fast for most use cases |

**Bottom line:** For "good enough" performance, Rails `send_file` is perfectly adequate.

### 8.2 Optimization Tips

If you need better performance later:

1. **Enable Puma workers:**
   ```ruby
   # config/puma.rb
   workers ENV.fetch("WEB_CONCURRENCY") { 2 }
   preload_app!
   ```

2. **Use CDN for static assets:**
   - Deploy `public/` to Cloudflare, AWS CloudFront, etc.
   - Configure Rails to use CDN URLs for assets

3. **Enable HTTP/2 upstream:**
   - Kamal's Caddy handles this automatically
   - Benefits: multiplexing, header compression, server push

4. **Enable compression:**
   ```ruby
   # config/environments/production.rb
   config.middleware.use Rack::Deflater
   ```

---

## Phase 9: Testing

### 9.1 Local Testing

```bash
# Build and run with new Dockerfile
docker-compose up --build

# Test basic endpoint
curl http://localhost:3000/

# Test file serving
curl -I http://localhost:3000/performers/1/image

# Test ActiveStorage file serving
curl -I http://localhost:3000/rails/active_storage/blobs/...

# Test static assets
curl -I http://localhost:3000/assets/application.css
```

### 9.2 Performance Testing

```bash
# Install wrk
brew install wrk

# Test streaming endpoint
wrk -t12 -c400 -d30s http://localhost:3000/performers/1/image

# Test static asset serving
wrk -t12 -c400 -d30s http://localhost:3000/assets/application.css
```

### 9.3 Production Testing

After deploying to production:

```bash
# Check SSL (handled upstream)
curl -I https://canister.example.com/

# Test healthcheck
curl http://localhost:3000/health

# Monitor logs
docker-compose logs -f web
```

---

## Migration Steps (Step-by-Step)

1. **Backup current deployment**
   ```bash
   git add .
   git commit -m "Backup before NGINX removal"
   ```

2. **Update Dockerfile** (Phase 1)

3. **Update docker-compose.yml** (Phase 2)

4. **Update Rails configuration** (Phase 3)

5. **Remove unused files** (Phase 5)

6. **Test locally**
   ```bash
   docker-compose up --build
   ```

7. **Deploy to production**
   - If using Kamal: `kamal setup && kamal deploy`
   - If using Docker Compose: `docker-compose -f docker-compose.prod.yml up -d`

8. **Monitor and verify**
   - Check logs: `docker-compose logs -f web`
   - Test endpoints
   - Monitor performance

---

## Benefits of This Approach

✅ **Simplified stack** - Ruby-only, no external dependencies
✅ **Easier development** - No need for NGINX locally
✅ **Smaller Docker image** - No Passenger/NGINX bloat
✅ **Better for CI/CD** - Simpler builds, faster deployments
✅ **Works everywhere** - Docker, bare metal, Kubernetes, VPS
✅ **Upstream SSL** - Let Caddy/Kamal handle certificates
✅ **Modern Rails** - Uses Rails 8.1 defaults

---

## Potential Issues & Solutions

| Issue | Solution |
|-------|----------|
| Video streaming slower than NGINX | Acceptable for your use case ("good enough"). Enable Puma workers if needed. |
| SSL/TLS setup complexity | Use Kamal or CloudFlare tunnel for automatic SSL |
| Static asset caching | Set proper cache headers, use CDN if needed |
| Memory usage | Tune `RAILS_MAX_THREADS` and `WEB_CONCURRENCY` |
| Connection limits | Puma handles thousands of connections with proper tuning |

---

## Summary

This plan removes **all NGINX and Passenger dependencies**, replacing them with:

- ✅ Pure Ruby stack (Puma + Rails)
- ✅ Direct file serving via `send_file`
- ✅ ActiveStorage with local disk service
- ✅ SSL/TLS handled upstream (Caddy, Kamal, etc.)
- ✅ Simplified Dockerfile and deployment

The result is a **simpler, more maintainable architecture** that aligns with your Ruby ecosystem preference while still providing "good enough" performance for video streaming.

---

## Next Steps

1. ✅ Review and approve this plan
2. ⏭️ Execute Phase 1-5 (Dockerfile, Compose, Rails config, cleanup)
3. ⏭️ Test locally
4. ⏭️ Deploy to production
5. ⏭️ Monitor and optimize as needed
