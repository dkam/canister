require "test_helper"

class ExportServiceTest < ActiveSupport::TestCase
  test "initializes with MediaManager" do
    service = ExportService.new
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
