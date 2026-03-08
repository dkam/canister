require "test_helper"

class ScanServiceTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Test", path: "/videos", kind: "local")
  end

  test "initializes with path and library" do
    service = ScanService.new(path: "test.mp4", library: @library)
    assert_instance_of ScanService, service
  end
end
