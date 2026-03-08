require "test_helper"

class CleanServiceTest < ActiveSupport::TestCase
  test "initializes with MediaManager" do
    service = CleanService.new
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
