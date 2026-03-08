require "test_helper"

class Library::KindDetectorTest < ActiveSupport::TestCase
  test "blank path returns local" do
    assert_equal "local", Library::KindDetector.new("").detect
    assert_equal "local", Library::KindDetector.new(nil).detect
  end

  test "absolute path returns local" do
    assert_equal "local", Library::KindDetector.new("/videos").detect
    assert_equal "local", Library::KindDetector.new("/mnt/media/movies").detect
  end

  test "relative path without scheme returns local" do
    assert_equal "local", Library::KindDetector.new("videos/movies").detect
  end

  test "s3 scheme returns s3" do
    assert_equal "s3", Library::KindDetector.new("s3://my-bucket/videos").detect
  end

  test "invalid URI returns local" do
    assert_equal "local", Library::KindDetector.new("ht tp://not valid").detect
  end

  test "http url with DAV header returns webdav" do
    http = fake_http("DAV" => "1,2")
    assert_equal "webdav", Library::KindDetector.new("http://example.com/dav", http_client: http).detect
  end

  test "https url with DAV header returns webdav" do
    http = fake_http("DAV" => "1")
    assert_equal "webdav", Library::KindDetector.new("https://example.com/dav", http_client: http).detect
  end

  test "http url without DAV header returns http" do
    http = fake_http({})
    assert_equal "http", Library::KindDetector.new("http://example.com/files", http_client: http).detect
  end

  test "connection error falls back to http" do
    http = Object.new
    http.define_singleton_method(:request) { |_| raise Errno::ECONNREFUSED }

    assert_equal "http", Library::KindDetector.new("http://example.com/files", http_client: http).detect
  end

  test "timeout falls back to http" do
    http = Object.new
    http.define_singleton_method(:request) { |_| raise Net::OpenTimeout }

    assert_equal "http", Library::KindDetector.new("http://example.com/files", http_client: http).detect
  end

  # VCR integration tests using recorded responses from real servers

  test "detects webdav from real server response" do
    VCR.use_cassette("rclone-webdav_options") do
      assert_equal "webdav", Library::KindDetector.new("http://192.168.1.10:8080/").detect
    end
  end

  test "detects http from real server response" do
    VCR.use_cassette("http_options") do
      assert_equal "http", Library::KindDetector.new("http://example.com/").detect
    end
  end

  test "passes basic auth credentials when provided" do
    captured_request = nil
    http = Object.new
    http.define_singleton_method(:request) do |req|
      captured_request = req
      response = Net::HTTPResponse.allocate
      response.define_singleton_method(:[]) { |_| nil }
      response
    end

    Library::KindDetector.new("http://example.com/dav", username: "user", password: "pass", http_client: http).detect

    assert captured_request["Authorization"].present?, "Expected Authorization header to be set"
  end

  private

  def fake_http(headers)
    header_map = headers.transform_keys(&:downcase)
    response = Net::HTTPResponse.allocate
    response.define_singleton_method(:[]) { |key| header_map[key.downcase] }

    http = Object.new
    http.define_singleton_method(:request) { |_| response }
    http
  end
end
