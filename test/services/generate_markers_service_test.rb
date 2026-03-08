require "test_helper"

class GenerateMarkersServiceTest < ActiveSupport::TestCase
  test "initializes with video" do
    video = videos(:video)
    service = GenerateMarkersService.new(video: video)
    assert_instance_of GenerateMarkersService, service
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
