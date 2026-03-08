class GenerateMarkersService
  def initialize(video:)
    @video = video
  end

  def start
    return unless has_markers
    create_folders

    Rails.logger.info("Video #{@video.id} has #{@video.video_markers.count} markers")

    output_width = 640

    @video.video_markers.each { |marker|
      duration_mp4 = marker.end_seconds.present? ? (marker.end_seconds - marker.seconds).to_i : 20
      duration_webp = marker.end_seconds.present? ? [(marker.end_seconds - marker.seconds).to_i, 5].min : 5

      marker_path = File.join(video_markers_path, "#{marker.seconds.to_i}.mp4")
      tmp_marker_path = File.join(temp_path, "#{marker.seconds.to_i}.mp4")

      ffmpeg_input = @video.ffmpeg_input
      input_arg = @video.local? ? "\"#{ffmpeg_input}\"" : "\"#{ffmpeg_input}\""

      if !File.exist?(marker_path)
        cmd = "ffmpeg -v quiet -ss #{marker.seconds.to_i} -t #{duration_mp4} -i #{input_arg} -c:v libx264 -profile:v high -level 4.2 -preset veryslow -crf 24 -movflags +faststart -threads 4 -vf scale=#{output_width}:-2 -sws_flags lanczos -c:a aac -b:a 64k -strict -2 '#{tmp_marker_path}'"
        Rails.logger.info("Creating marker video #{marker_path}")
        unless system(cmd)
          Rails.logger.error("Error running ffmpeg #{$?}")
        end

        FileUtils.mv(tmp_marker_path, marker_path)
      end

      marker_path = File.join(video_markers_path, "#{marker.seconds.to_i}.webp")
      tmp_marker_path = File.join(temp_path, "#{marker.seconds.to_i}.webp")
      if !File.exist?(marker_path)
        cmd = "ffmpeg -v quiet -ss #{marker.seconds.to_i} -t #{duration_webp} -i #{input_arg} -c:v libwebp -lossless 1 -q:v 70 -compression_level 6 -preset default -loop 0 -threads 4 -vf scale=#{output_width}:-2,fps=12 -an '#{tmp_marker_path}'"
        Rails.logger.info("Creating marker image #{marker_path}")
        unless system(cmd)
          Rails.logger.error("Error running ffmpeg #{$?}")
        end

        FileUtils.mv(tmp_marker_path, marker_path)
      end
    }

    @video
  end

  private

  def create_folders
    FileUtils.mkdir_p(Canister::STASH_MARKERS_DIRECTORY) unless File.directory?(Canister::STASH_MARKERS_DIRECTORY)
    FileUtils.mkdir_p(temp_path) unless File.directory?(temp_path)
    FileUtils.mkdir_p(video_markers_path) unless File.directory?(video_markers_path)
  end

  def temp_path
    File.join(Canister::STASH_MARKERS_DIRECTORY, "tmp")
  end

  def video_markers_path
    File.join(Canister::STASH_MARKERS_DIRECTORY, @video.id.to_s)
  end

  def has_markers
    @video.video_markers.count > 0
  end
end
