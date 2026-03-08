require "test_helper"

class GenerateSpriteServiceTest < ActiveSupport::TestCase
  test "initializes with video" do
    video = videos(:video)
    service = GenerateSpriteService.new(video: video)
    assert_instance_of GenerateSpriteService, service
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end

  test "start is a no-op" do
    video = videos(:video)
    service = GenerateSpriteService.new(video: video)
    assert_nil service.start
  end
end
