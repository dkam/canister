require "test_helper"

class GeneratePreviewServiceTest < ActiveSupport::TestCase
  test "initializes with video" do
    video = videos(:video)
    service = GeneratePreviewService.new(video: video)
    assert_instance_of GeneratePreviewService, service
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
