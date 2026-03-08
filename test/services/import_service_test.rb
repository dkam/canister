require "test_helper"

class ImportServiceTest < ActiveSupport::TestCase
  test "initializes" do
    service = ImportService.new
    assert_instance_of ImportService, service
  end
end
