 Live Remux Streaming Plan

 Context

 Videos in MKV/AVI containers with H.264/H.265 codecs don't play in browsers because the container isn't supported, not the codec. Currently PrepareVideoJob
 pre-generates a remuxed MP4 for these files — but remuxing is I/O-only (no decode/encode), so it can be done live on every request in seconds with minimal
 CPU. Pre-generating just to fix the container is unnecessary overhead.

 The new approach:
 - Compatible codec + streamable container → send_file directly (unchanged, range requests work)
 - Compatible codec + wrong container → live remux via ActionController::Live + ffmpeg pipe with frag_keyframe+empty_moov; Video.js intercepts seeks and
 reloads with ?start=X
 - Pre-generated transcode exists → send_file transcode (unchanged)
 - Incompatible codec (Xvid, MPEG-2 etc.) → not playable; PrepareVideoJob kept for explicit user-triggered transcode (UI button is future work)

 Stash uses this same live approach for all non-direct streams (frag_keyframe+empty_moov + ?start= seeking). See tmp/stash/pkg/ffmpeg/stream_transcode.go line
  100 and tmp/stash/ui/v2.5/src/components/ScenePlayer/live.ts.

 ---
 Files to Modify

 ┌─────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────┐
 │                      File                       │                             Change                             │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/controllers/scenes_controller.rb            │ Add stream_live action with ActionController::Live             │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ config/routes.rb                                │ Add get :stream_live member route                              │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/models/scene.rb                             │ Add needs_remux?, needs_transcode?; update is_streamable       │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/views/scenes/show.html.erb                  │ Use stream_live URL + data-player-live-value when remux needed │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/javascript/controllers/player_controller.js │ Add timestamp-based seeking for live streams                   │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/lib/canister/tasks/prepare_video.rb         │ Remove remux path; transcode only                              │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/jobs/process_videos_job.rb                  │ Update needing_processing scope to exclude remux-only files    │
 ├─────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
 │ app/models/scene.rb                             │ Update needing_processing scope to transcode-only              │
 └─────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────┘

 ---
 Implementation

 1. Scene model (app/models/scene.rb)

 Add public helpers:

 def needs_remux?
   !File.exist?(transcode_path) &&
     Canister::VALID_HTML5_CODECS.include?(video_codec) &&
     !Canister::STREAMABLE_EXTENSIONS.include?(File.extname(path).downcase)
 end

 def needs_transcode?
   !File.exist?(transcode_path) &&
     !Canister::VALID_HTML5_CODECS.include?(video_codec)
 end

 Update is_streamable — any file with a compatible codec is now effectively streamable (live remux handles the container):

 def is_streamable
   return true if File.exist?(transcode_path)
   Canister::VALID_HTML5_CODECS.include?(video_codec)
 end

 Update needing_processing scope to transcode-only (remux is now live):

 scope :needing_processing, -> {
   where.not(video_codec: Canister::VALID_HTML5_CODECS)
 }

 Make transcode_path public (needed by view to check existence).

 2. Routes (config/routes.rb)

 resources :scenes, only: [:index, :show] do
   member do
     get :stream
     get :stream_live   # new
     # ... existing routes
   end
 end

 3. Controller (app/controllers/scenes_controller.rb)

 Add ActionController::Live and the stream_live action. Keep existing stream action unchanged.

 include ActionController::Live

 def stream_live
   start_time = params[:start].to_f

   cmd = %w[ffmpeg -hide_banner -loglevel error]
   cmd += ['-ss', start_time.to_s] if start_time > 0
   cmd += ['-i', @scene.path, '-c', 'copy',
           '-movflags', 'frag_keyframe+empty_moov',
           '-f', 'mp4', 'pipe:1']

   response.headers['Content-Type'] = 'video/mp4'
   response.headers['Cache-Control'] = 'no-store'
   response.headers['Accept-Ranges'] = 'none'

   IO.popen(cmd) do |ffmpeg|
     until ffmpeg.eof?
       response.stream.write(ffmpeg.read(16_384))
     end
   end
 rescue ActionController::Live::ClientDisconnected, Errno::EPIPE
   # client disconnected; IO.popen block exit sends SIGPIPE to ffmpeg
 ensure
   response.stream.close
 end

 Add stream_live to before_action :set_scene.

 4. View (app/views/scenes/show.html.erb)

 Pass the right stream URL and whether seeking should use timestamps:

 <div id="scene-player"
      data-controller="player"
      data-player-src-value="<%= @scene.needs_remux? ? stream_live_scene_path(@scene) : stream_scene_path(@scene) %>"
      data-player-live-value="<%= @scene.needs_remux? %>"
      ...>

 5. Player controller (app/javascript/controllers/player_controller.js)

 Add live value and timestamp-based seeking:

 static values = {
   src: String,
   poster: String,
   vtt: String,
   sceneId: Number,
   title: String,
   live: { type: Boolean, default: false }
 }

 connect() {
   // ... existing setup ...
   if (this.liveValue) {
     this.player.on('seeking', () => this._handleLiveSeek())
   }
 }

 _handleLiveSeek() {
   const currentTime = this.player.currentTime()
   const buffered = this.player.buffered()

   // Don't reload if seek point is already buffered
   for (let i = 0; i < buffered.length; i++) {
     if (currentTime >= buffered.start(i) && currentTime <= buffered.end(i)) return
   }

   const url = new URL(this.srcValue, window.location.origin)
   url.searchParams.set('start', Math.floor(currentTime).toString())
   this.player.src([{ src: url.toString(), type: 'video/mp4' }])
   this.player.play()
 }

 6. PrepareVideo task (app/lib/canister/tasks/prepare_video.rb)

 Remove the remux path entirely. start should only transcode:

 def start
   return if has_transcode?
   return if Canister::VALID_HTML5_CODECS.include?(@scene.video_codec) # remux handled live
   transcode
 end

 ---
 What Doesn't Change

 - PrepareVideoJob / ProcessVideosJob — still used for explicit transcode of incompatible codecs
 - stream action — unchanged, still serves direct files and pre-generated transcodes via send_file
 - Range request support for pre-generated files — unchanged
 - metadata:process_videos rake task — still works, now only queues actual transcodes

 ---
 Verification

 1. Open an MKV+H.264 scene — video should play without any pre-generated transcode file
 2. Seek to a point outside the buffer — video should resume from that timestamp (brief re-buffer expected)
 3. Seek within the buffered range — should seek instantly without reloading
 4. Open an MP4+H.264 scene — should serve directly via send_file, range requests work normally
 5. Check that rails metadata:process_videos only queues scenes with incompatible codecs
 6. Verify ffmpeg process is killed when browser tab is closed (check for orphan processes)
