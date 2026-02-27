# Canister

A Rails API server that organizes, serves, and streams your video collection.

Canister is a reboot of [StashServer](https://github.com/stashapp/StashServer) by [stashapp](https://github.com/stashapp), originally built to organize and serve adult content. The codebase has been modernized and broadened to support all video types.

> The original project has since been rewritten in Go as [stashapp/stash](https://github.com/stashapp/stash).

## Setup

```bash
bundle install
```

Create `config/application.yml`:

```yaml
stash_directory: ''
stash_metadata_directory: ''
stash_cache_directory: ''
stash_downloads_directory: ''
```

```bash
rails s
```

## Rake Tasks

```bash
rails metadata:scan              # scan video directory, checksum files, generate thumbnails
rails metadata:import            # drop DB and reimport from metadata JSON
rails metadata:export            # export DB to metadata JSON
rails metadata:generate_sprites  # VTT sprite sheets for timeline scrubbing
rails metadata:generate_previews # MP4 preview clips
rails metadata:generate_marker_previews
rails metadata:generate_transcodes  # transcode non-HTML5 formats (e.g. wmv)
rails metadata:generate_all      # run all generate tasks
rails metadata:cleanup           # remove generated files for deleted scenes
```
