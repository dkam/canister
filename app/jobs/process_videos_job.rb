class ProcessVideosJob < ApplicationJob
  queue_as :default

  def perform
    Scene.needing_processing.each do |scene|
      PrepareVideoJob.perform_later(scene.id)
    end
  end
end
