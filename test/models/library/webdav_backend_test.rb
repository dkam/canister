require "test_helper"

class Library::WebdavBackendTest < ActiveSupport::TestCaseWithoutFixtures
  PROPFIND_RESPONSE = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <D:multistatus xmlns:D="DAV:">
      <D:response>
        <D:href>/</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname></D:displayname>
            <D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
      <D:response>
        <D:href>/$6%20Michelin%20Stock.webm</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname>$6 Michelin Stock.webm</D:displayname>
            <D:resourcetype></D:resourcetype>
            <D:getcontentlength>861877901</D:getcontentlength>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
      <D:response>
        <D:href>/.metube/</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname>.metube</D:displayname>
            <D:resourcetype><D:collection xmlns:D="DAV:"/></D:resourcetype>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
      <D:response>
        <D:href>/subfolder/video.mp4</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname>video.mp4</D:displayname>
            <D:resourcetype></D:resourcetype>
            <D:getcontentlength>225328598</D:getcontentlength>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
      <D:response>
        <D:href>/Tommy%20Tiernan%20%E2%9D%A4%EF%B8%8F%20RT%C3%89.mp4</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname>Tommy Tiernan \u2764\uFE0F RT\u00C9.mp4</D:displayname>
            <D:resourcetype></D:resourcetype>
            <D:getcontentlength>123456</D:getcontentlength>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
      <D:response>
        <D:href>/photo.jpg</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname>photo.jpg</D:displayname>
            <D:resourcetype></D:resourcetype>
            <D:getcontentlength>54321</D:getcontentlength>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
      <D:response>
        <D:href>/.metube/queue</D:href>
        <D:propstat>
          <D:prop>
            <D:displayname>queue</D:displayname>
            <D:resourcetype></D:resourcetype>
            <D:getcontentlength>0</D:getcontentlength>
          </D:prop>
          <D:status>HTTP/1.1 200 OK</D:status>
        </D:propstat>
      </D:response>
    </D:multistatus>
  XML

  setup do
    @library = Library.new(name: "Test WebDAV", path: "http://192.168.1.10:8080/", kind: "webdav")
    @backend = Library::WebdavBackend.new(@library)
  end

  test "parse_propfind_response extracts files matching extensions" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, %w[mp4 webm])

    assert_includes paths, "$6 Michelin Stock.webm"
    assert_includes paths, "subfolder/video.mp4"
    assert_equal 3, paths.size
  end

  test "parse_propfind_response excludes collections" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, %w[mp4 webm mkv avi])

    paths.each do |path|
      refute path.end_with?("/"), "Should not include collection: #{path}"
    end
  end

  test "parse_propfind_response excludes non-matching extensions" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, %w[mp4 webm])

    refute paths.any? { |p| p.end_with?(".jpg") }, "Should not include .jpg files"
  end

  test "parse_propfind_response decodes URL-encoded paths" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, %w[mp4 webm])

    assert paths.any? { |p| p.include?("$6 Michelin") }, "Should decode %20 to spaces"
  end

  test "parse_propfind_response decodes unicode characters" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, %w[mp4])

    unicode_path = paths.find { |p| p.include?("Tommy") }
    assert unicode_path, "Should find Tommy Tiernan file"
    assert unicode_path.include?("\u00C9"), "Should decode UTF-8 encoded characters"
  end

  test "parse_propfind_response strips leading slash" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, %w[mp4 webm])

    paths.each do |path|
      refute path.start_with?("/"), "Path should not start with /: #{path}"
    end
  end

  test "parse_propfind_response with empty extensions returns no files" do
    paths = @backend.send(:parse_propfind_response, PROPFIND_RESPONSE, [])

    assert_empty paths
  end

  test "build_uri encodes special characters in path segments" do
    uri = @backend.send(:build_uri, "$6 Michelin Stock (Costco Hack).webm")
    assert_equal "http://192.168.1.10:8080/%246%20Michelin%20Stock%20%28Costco%20Hack%29.webm", uri.to_s
  end

  test "build_uri preserves path separators" do
    uri = @backend.send(:build_uri, "subfolder/my video.mp4")
    assert_equal "http://192.168.1.10:8080/subfolder/my%20video.mp4", uri.to_s
  end

  test "build_uri preserves plus signs as %2B" do
    uri = @backend.send(:build_uri, "C+C Music Factory.mkv")
    assert_equal "http://192.168.1.10:8080/C%2BC%20Music%20Factory.mkv", uri.to_s
  end

  test "ffmpeg_input encodes special characters" do
    url = @backend.ffmpeg_input("$6 Michelin Stock (Costco Hack).webm")
    assert_includes url, "%246"
    assert_includes url, "%28"
  end

  test "ffmpeg_input builds authenticated URL" do
    @library.username = "user"
    @library.password = "pass"

    url = @backend.ffmpeg_input("subfolder/video.mp4")

    assert_equal "http://user:pass@192.168.1.10:8080/subfolder/video.mp4", url
  end

  test "ffmpeg_input builds URL without auth when no credentials" do
    url = @backend.ffmpeg_input("video.mp4")

    assert_equal "http://192.168.1.10:8080/video.mp4", url
  end

  test "local? returns false" do
    refute @backend.local?
  end

  test "remote? returns true" do
    assert @backend.remote?
  end
end
