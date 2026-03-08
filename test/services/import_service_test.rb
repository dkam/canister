require "test_helper"

class ImportServiceTest < ActiveSupport::TestCase
  test "initializes with MediaManager" do
    service = ImportService.new
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
