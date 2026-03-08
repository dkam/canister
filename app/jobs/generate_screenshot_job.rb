class GenerateScreenshotJob < ApplicationJob
  queue_as :media

  def perform(video_id, timecode = nil)
    video = Video.find(video_id)
    video.probe! unless video.probed?

    ffmpeg_path = video.ffmpeg_input
    movie = FFMPEG::Movie.new(ffmpeg_path)
    timecode ||= video.duration * 0.2

    Tempfile.create(["screenshot", ".jpg"]) do |tmp|
      transcoder_options = { input_options: { v: "quiet", ss: timecode.to_s } }
      options = { screenshot: true, quality: 2, custom: %W[-vf scale=#{movie.width}:-1] }
      movie.transcode(tmp.path, options, transcoder_options)

      screenshot = video.screenshots.build(timecode: timecode)
      screenshot.image.attach(
        io: File.open(tmp.path),
        filename: "screenshot_#{(timecode * 1000).to_i}ms.jpg",
        content_type: "image/jpeg"
      )
      screenshot.save!
    end
  end
end
