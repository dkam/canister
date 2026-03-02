require "net/http"
require "uri"
require "cgi"

class Library::WebdavBackend < Library::Backend
  def list_files(extensions:)
    response = propfind("/")
    return [] unless response.is_a?(Net::HTTPSuccess)

    parse_propfind_response(response.body, extensions)
  rescue => e
    Rails.logger.error "WebDAV list_files error: #{e.message}"
    []
  end

  def file_exists?(relative_path)
    response = head(relative_path)
    response.is_a?(Net::HTTPSuccess)
  rescue
    false
  end

  def ffmpeg_input(relative_path)
    uri = build_uri(relative_path)
    uri.user = library.username
    uri.password = library.password
    uri.to_s
  end

  def file_size(relative_path)
    response = head(relative_path)
    return nil unless response.is_a?(Net::HTTPSuccess)

    response["Content-Length"]&.to_i
  rescue
    nil
  end

  def read_range(relative_path, range)
    uri = build_uri(relative_path)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth(library.username, library.password) if library.username.present?

    if range.is_a?(Range)
      request["Range"] = "bytes=#{range.begin}-#{range.end}"
    elsif range.is_a?(Integer)
      request["Range"] = "bytes=#{range}-#{range + 64 * 1024 - 1}"
    end

    response = http.request(request)
    response.is_a?(Net::HTTPSuccess) ? response.body : nil
  rescue => e
    Rails.logger.error "WebDAV read_range error: #{e.message}"
    nil
  end

  def absolute_path(relative_path)
    nil
  end

  def local?
    false
  end

  private

  def propfind(path)
    uri = URI.join(library.path, path)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Propfind.new(uri.request_uri)
    request.basic_auth(library.username, library.password) if library.username.present?
    request["Depth"] = "infinity"
    request["Content-Type"] = "application/xml"
    request.body = '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>'

    http.request(request)
  end

  def head(relative_path)
    uri = build_uri(relative_path)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"

    request = Net::HTTP::Head.new(uri.request_uri)
    request.basic_auth(library.username, library.password) if library.username.present?

    http.request(request)
  end

  def build_uri(relative_path)
    encoded = relative_path.split("/").map { |segment| URI.encode_uri_component(segment) }.join("/")
    URI.join(library.path, encoded)
  end

  def parse_propfind_response(body, extensions)
    require "nokogiri"

    doc = Nokogiri::XML(body)
    doc.remove_namespaces!

    responses = doc.xpath("//response")
    responses.map do |resp|
      href = resp.xpath("./href").text
      resource_type = resp.xpath("./propstat/prop/resourcetype")
      is_collection = resource_type.children.any? { |c| c.name == "collection" }

      next nil if is_collection

      ext = File.extname(href).downcase.delete_prefix(".")
      next nil unless extensions.map(&:downcase).include?(ext)

      CGI.unescape(href).sub(%r{^/}, "")
    end.compact
  end
end
