require "test_helper"

class TranscodeServiceTest < ActiveSupport::TestCase
  test "initializes with video" do
    video = videos(:video)
    service = TranscodeService.new(video: video)
    assert_instance_of TranscodeService, service
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
