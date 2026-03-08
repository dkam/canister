class GenerateScreenshotJob < ApplicationJob
  queue_as :media

  def perform(video_id, timecode = nil)
    video = Video.find(video_id)
    ScreenshotService.generate(video, seconds: timecode)
  end
end
