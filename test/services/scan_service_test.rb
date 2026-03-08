require "test_helper"

class ScanServiceTest < ActiveSupport::TestCase
  setup do
    @library = Library.create!(name: "Test", path: "/videos", kind: "local")
  end

  test "initializes with path and library" do
    service = ScanService.new(path: "test.mp4", library: @library)
    assert_instance_of ScanService, service
  end

  test "uses MediaManager singleton" do
    service = ScanService.new(path: "test.mp4", library: @library)
    assert_instance_of MediaManager, service.instance_variable_get(:@manager)
  end
end
