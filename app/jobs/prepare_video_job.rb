class PrepareVideoJob < ApplicationJob
  queue_as :media

  def perform(scene_id)
    scene = Scene.find(scene_id)
    Canister::Tasks::PrepareVideo.new(scene: scene).start
  end
end
