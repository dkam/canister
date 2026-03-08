require "test_helper"

class JsonUtilityTest < ActiveSupport::TestCase
  test "is a module" do
    assert_kind_of Module, JsonUtility
  end

  test "person returns nil when file does not exist" do
    assert_nil JsonUtility.person("nonexistent_id")
  end

  test "video returns nil when file does not exist" do
    assert_nil JsonUtility.video("nonexistent_id")
  end

  test "gallery returns nil when file does not exist" do
    assert_nil JsonUtility.gallery("nonexistent_id")
  end

  test "studio returns nil when file does not exist" do
    assert_nil JsonUtility.studio("nonexistent_id")
  end
end
