require "fileutils"
require "tmpdir"
require "zip"
require "naturally"

module Canister
  TRANSCODE_DIRECTORY = ENV.fetch('TRANSCODE_PATH', Rails.root.join('transcodes').to_s)

  VALID_HTML5_CODECS = ["h264", "h265", "vp8", "vp9"]
end
