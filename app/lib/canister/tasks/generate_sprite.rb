class Canister::Tasks::GenerateSprite < Canister::Tasks::Base
  def initialize(scene:)
    super()
    @scene = scene
  end

  def start
    # TODO: reimplement sprite/VTT generation with ActiveStorage
  end
end
