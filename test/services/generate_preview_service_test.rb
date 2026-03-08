require "test_helper"

class GeneratePreviewServiceTest < ActiveSupport::TestCase
  test "initializes with video" do
    video = videos(:video)
    service = GeneratePreviewService.new(video: video)
    assert_instance_of GeneratePreviewService, service
  end
end
