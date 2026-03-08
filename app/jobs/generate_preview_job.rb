class GeneratePreviewJob < ApplicationJob
  queue_as :media

  def perform(video_id)
    video = Video.find(video_id)
    GeneratePreviewService.new(video: video).start
  end
end
