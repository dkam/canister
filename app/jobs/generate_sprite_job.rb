class GenerateSpriteJob < ApplicationJob
  queue_as :media

  def perform(video_id)
    video = Video.find(video_id)
    GenerateSpriteService.new(video: video).start
  end
end
