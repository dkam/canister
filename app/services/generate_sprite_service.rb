class GenerateSpriteService
  def initialize(video:)
    @manager = MediaManager.instance
    @video = video
  end

  def start
    # TODO: reimplement sprite/VTT generation with ActiveStorage
  end
end
