class TranscodeJob < ApplicationJob
  queue_as :media

  def perform(video_id)
    video = Video.find(video_id)
    TranscodeService.new(video: video).start
  end
end
