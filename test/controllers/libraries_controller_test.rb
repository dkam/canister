require "test_helper"

class LibrariesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @library = Library.create!(name: "Test Library", path: "/videos", kind: "local")
    MediaManager.instance.send(:idle)
  end

  test "GET index" do
    get libraries_path
    assert_response :success
    assert_select "table"
    assert_select "a", text: "Test Library"
  end

  test "GET index with no libraries shows empty state" do
    Library.destroy_all
    get libraries_path
    assert_response :success
    assert_select "a", text: "Create your first library"
  end

  test "GET show" do
    get library_path(@library)
    assert_response :success
    assert_select "h1", text: @library.name
  end

  test "GET new" do
    get new_library_path
    assert_response :success
    assert_select "form"
  end

  test "POST create with valid params" do
    assert_difference("Library.count") do
      post libraries_path, params: { library: { name: "New Lib", path: "/new", kind: "local" } }
    end
    assert_redirected_to library_path(Library.last)
    follow_redirect!
    assert_select "div", /Library created. Scan queued./
  end

  test "POST create with invalid params renders form" do
    assert_no_difference("Library.count") do
      post libraries_path, params: { library: { name: "", path: "", kind: "local" } }
    end
    assert_response :unprocessable_entity
  end

  test "GET edit" do
    get edit_library_path(@library)
    assert_response :success
    assert_select "form"
  end

  test "PATCH update with valid params" do
    patch library_path(@library), params: { library: { name: "Renamed" } }
    assert_redirected_to library_path(@library)
    assert_equal "Renamed", @library.reload.name
  end

  test "PATCH update with blank password preserves existing password" do
    @library.update!(password: "secret")
    patch library_path(@library), params: { library: { name: "Same", password: "" } }
    assert_redirected_to library_path(@library)
    assert_equal "secret", @library.reload.password
  end

  test "PATCH update with new password changes it" do
    @library.update!(password: "old")
    patch library_path(@library), params: { library: { password: "new" } }
    assert_redirected_to library_path(@library)
    assert_equal "new", @library.reload.password
  end

  test "DELETE destroy" do
    assert_difference("Library.count", -1) do
      delete library_path(@library)
    end
    assert_redirected_to libraries_path
  end

  test "DELETE destroy nullifies videos" do
    video = Video.new(path: "test/video.mp4", library: @library)
    video.checksums.build(checksum_type: :opensubtitles, hash_value: "abc123")
    video.save!
    delete library_path(@library)
    assert_nil video.reload.library_id
  end

  test "POST scan enqueues job" do
    assert_enqueued_with(job: ScanJob, args: [@library.id]) do
      post scan_library_path(@library)
    end
    assert_redirected_to library_path(@library)
  end
end
