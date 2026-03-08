require "test_helper"

class ExportServiceTest < ActiveSupport::TestCase
  test "initializes" do
    service = ExportService.new
    assert_instance_of ExportService, service
  end
end
