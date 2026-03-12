require "streamio-ffmpeg"

class ScreenshotService
  # Generate a screenshot and attach it to a Screenshot model via ActiveStorage
  def self.generate(video, seconds: nil, width: nil)
    video.probe! unless video.probed?
    return unless video.duration

    ffmpeg_path = video.ffmpeg_input
    movie = FFMPEG::Movie.new(ffmpeg_path)
    seconds ||= video.duration * 0.2
    width ||= movie.width

    Tempfile.create(["screenshot", ".jpg"]) do |tmp|
      transcoder_options = { input_options: { v: "quiet", ss: seconds.to_s } }
      options = { screenshot: true, quality: 2, custom: %W[-vf scale=#{width}:-1] }
      movie.transcode(tmp.path, options, transcoder_options)

      screenshot = video.screenshots.build(timecode: seconds)
      screenshot.image.attach(
        io: File.open(tmp.path),
        filename: "screenshot_#{(seconds * 1000).to_i}ms.jpg",
        content_type: "image/jpeg"
      )
      screenshot.save!
    end
  end

  # Return raw JPEG bytes for on-demand streaming
  def self.generate_bytes(path:, seconds: nil, width: nil)
    movie = FFMPEG::Movie.new(path)
    width ||= movie.width
    unless seconds && seconds.to_i < movie.duration.to_i
      seconds = movie.duration * 0.2
    end

    escaped = Shellwords.escape(path)
    `ffmpeg -v quiet -ss #{seconds} -i #{escaped} -vframes 1 -q:v 2 -vf scale='#{width}:-1' -f image2pipe pipe:1`
  end
end
