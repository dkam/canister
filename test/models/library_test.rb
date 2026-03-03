require "test_helper"

class LibraryTest < ActiveSupport::TestCaseWithoutFixtures
  include ActiveJob::TestHelper
  test "validates name presence" do
    library = Library.new(path: "/videos", kind: "local")
    refute library.valid?
    assert library.errors[:name].any?
  end

  test "validates path presence" do
    library = Library.new(name: "Test", kind: "local")
    refute library.valid?
    assert library.errors[:path].any?
  end

  test "valid with name, path, and kind" do
    library = Library.new(name: "Test", path: "/videos", kind: "local")
    assert library.valid?
  end

  test "backend returns LocalBackend for local kind" do
    library = Library.new(name: "Test", path: "/videos", kind: "local")
    assert_instance_of Library::LocalBackend, library.backend
  end

  test "backend returns WebdavBackend for webdav kind" do
    library = Library.new(name: "Test", path: "http://example.com/", kind: "webdav")
    assert_instance_of Library::WebdavBackend, library.backend
  end

  test "backend raises for unsupported kind" do
    library = Library.new(name: "Test", path: "/videos", kind: "s3")
    assert_raises(RuntimeError) { library.backend }
  end

  test "local? returns true for local kind" do
    library = Library.new(kind: "local")
    assert library.local?
  end

  test "local? returns false for webdav kind" do
    library = Library.new(kind: "webdav")
    refute library.local?
  end

  test "remote? is inverse of local?" do
    assert Library.new(kind: "webdav").remote?
    refute Library.new(kind: "local").remote?
  end

  test "destroying library nullifies scene library_id" do
    library = Library.create!(name: "Test", path: "/videos", kind: "local")
    scene = Scene.new(path: "test/video.mp4", library: library)
    scene.checksums.build(checksum_type: :opensubtitles, hash_value: "abc123")
    scene.save!

    library.destroy!
    scene.reload

    assert_nil scene.library_id
  end

  test "scan enqueues ScanJob with library id" do
    library = Library.create!(name: "Test", path: "/videos", kind: "local")

    assert_enqueued_with(job: ScanJob, args: [library.id]) do
      library.scan
    end
  end
end
