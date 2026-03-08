require "test_helper"

class CleanServiceTest < ActiveSupport::TestCase
  test "initializes" do
    service = CleanService.new
    assert_instance_of CleanService, service
  end
end
