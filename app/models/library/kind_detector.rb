class Library::KindDetector
  def initialize(path, username: nil, password: nil, http_client: nil)
    @path = path
    @username = username
    @password = password
    @http_client = http_client
  end

  def detect
    return "local" if local_path?
    return "s3" if @path.start_with?("s3://")

    uri = URI.parse(@path)
    return "local" unless %w[http https].include?(uri.scheme)

    webdav?(uri) ? "webdav" : "http"
  rescue URI::InvalidURIError
    "local"
  end

  private

  def local_path?
    @path.blank? || @path.start_with?("/") || !@path.include?("://")
  end

  def webdav?(uri)
    http = @http_client || build_http(uri)

    request = Net::HTTP::Options.new(uri.request_uri)
    request.basic_auth(@username, @password) if @username.present?

    response = http.request(request)
    response["DAV"].present?
  rescue
    false
  end

  def build_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 5
    http
  end
end
