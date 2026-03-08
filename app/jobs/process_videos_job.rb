class ProcessVideosJob < ApplicationJob
  queue_as :default

  def perform
    Video.needing_processing.each do |video|
      TranscodeJob.perform_later(video.id)
    end
  end
end
