require "test_helper"

class GenerateMarkersServiceTest < ActiveSupport::TestCase
  test "initializes with video" do
    video = videos(:video)
    service = GenerateMarkersService.new(video: video)
    assert_instance_of GenerateMarkersService, service
  end
end
