# This version works with files and urls. For URLs, it only downloads the chunks 
# of the file neccessary to calculate the hash.
#
# Author: Dan Milne

require "net/http"
require "uri"

module OpenSubtitlesHash
  class Error < StandardError; end
  class FileNotFoundError < Error; end
  class NetworkError < Error; end

  CHUNK_SIZE = 64 * 1024 # in bytes

  def self.compute_hash(url)
    data = url.start_with?("http") ? data_from_url(url) : data_from_file(url)

    hash = data[:filesize]

    hash = process_chunk(data.dig(:chunks, 0), hash)
    hash = process_chunk(data.dig(:chunks, 1), hash)

    format("%016x", hash)
  end

  def self.data_from_file(path)
    filesize = File.size(path)

    data = { filesize: filesize, chunks: [] }

    File.open(path, "rb") do |f|
      data[:chunks] << f.read(CHUNK_SIZE)
      f.seek([0, filesize - CHUNK_SIZE].max, IO::SEEK_SET)
      data[:chunks] << f.read(CHUNK_SIZE)
    end

    data
  end

  def self.data_from_url(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")

    # Get the file size
    response = http.request_head(uri.path)
    filesize = response["content-length"].to_i

    data = { filesize: filesize, chunks: [] }

    # Process the beginning of the file
    response = http.get(uri.path, { "Range" => "bytes=0-#{CHUNK_SIZE - 1}" })
    data[:chunks] << response.body

    # Process the end of the file
    start_byte = [0, filesize - CHUNK_SIZE].max
    response = http.get(uri.path, { "Range" => "bytes=#{start_byte}-#{filesize - 1}" })
    data[:chunks] << response.body

    data
  end

  def self.process_chunk(chunk, hash)
    chunk.unpack("Q*").each do |n|
      hash = hash + n & 0xffffffffffffffff
    end

    hash
  end
end
