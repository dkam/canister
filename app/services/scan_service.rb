# Scanning pipeline for importing media files into the database.
#
# ScanService.run iterates library files and for each new video:
#   1. Checksum  — compute OpenSubtitles hash (sync, ~275ms remote)
#   2. DB insert — create Video record with path + checksum only
#   3. Enqueue background jobs (all on :media queue):
#      a. ProbeVideoJob      — ffprobe metadata (duration, codecs, resolution)
#      b. GenerateScreenshotJob — screenshot at 20% (or custom timecode)
#      c. GeneratePreviewJob — animated preview clip
#
# Jobs are idempotent:
#   - ProbeVideoJob skips if duration is already set (video.probed?)
#   - GenerateScreenshotJob calls video.probe! inline if probe hasn't run yet
#
class ScanService
  class LogSubscriber < ActiveSupport::LogSubscriber
    def list_files(event)
      info "  List files (#{event.duration.round(1)}ms) #{event.payload[:library]}"
    end

    def checksum(event)
      info "  Checksum (#{event.duration.round(1)}ms) #{event.payload[:path]}"
    end

  end

  LogSubscriber.attach_to :scan_service

  def self.run(library_id: nil)
    libraries = library_id ? Library.where(id: library_id) : Library.all
    libraries.each do |library|
      scan_paths = ActiveSupport::Notifications.instrument("list_files.scan_service", library: library.name) do
        library.backend.list_files(extensions: Canister::MEDIA_EXTENSIONS)
      end
      Rails.logger.info("Starting scan of #{scan_paths.count} files in #{library.name} (#{library.path})")
      scan_paths.each do |relative_path|
        ScanService.new(path: relative_path, library: library).start
      rescue ScriptError, StandardError => e
        Rails.logger.error("Error scanning #{relative_path}: #{e.inspect} --> #{e.backtrace&.first}")
      end
    end
  end

  def initialize(path:, library:)
    @path = path
    @library = library
    @backend = library&.backend
  end

  def start
    @klass = path_class

    item = @klass.find_by(path: @path)
    if item
      GenerateScreenshotJob.perform_later(item.id) if @klass == Video && item.screenshots.none?
      return nil
    end

    checksum = ActiveSupport::Notifications.instrument("checksum.scan_service", path: @path) do
      calculate_checksum
    end

    existing_item = Checksum.find_by(hash_value: checksum, checksum_type: :opensubtitles, hashable_type: @klass.to_s)&.hashable

    if existing_item
      Rails.logger.info("#{@path} already exists.  Updating path...")
      existing_item.update(path: @path)
      GenerateScreenshotJob.perform_later(existing_item.id) if existing_item.is_a?(Video) && existing_item.screenshots.none?
      return nil
    end

    Rails.logger.info("#{@path} doesn't exist.  Creating new item...")
    item = @klass.new(path: @path, library: (@library if @klass == Video))

    item.checksums.build(checksum_type: :opensubtitles, hash_value: checksum)
    item.save!

    if @klass == Video
      ProbeVideoJob.perform_later(item.id)
      GenerateScreenshotJob.perform_later(item.id)
      GeneratePreviewJob.perform_later(item.id)
    end

    @path
  end

  private

  def path_class
    (File.extname(@path) == ".zip") ? Gallery : Video
  end

  def calculate_checksum
    Rails.logger.info("#{@path} not found.  Calculating checksum...")

    require "open_subtitles_hash"

    absolute_path = @backend&.absolute_path(@path) || @path

    if @backend&.local? || @backend.nil?
      OpenSubtitlesHash.compute_hash(absolute_path).downcase
    else
      calculate_remote_opensubtitles_hash
    end
  end

  def calculate_remote_opensubtitles_hash
    first_64k = @backend.read_range(@path, 0)
    file_size = @backend.file_size(@path)

    return "0" * 16 unless first_64k && file_size

    last_64k = @backend.read_range(@path, file_size - 65536..file_size - 1)
    return "0" * 16 unless last_64k

    data = first_64k + last_64k

    sum = 0
    data.unpack("Q<*").each { |n| sum += n }

    ((sum + file_size) & 0xffffffffffffffff).to_s(16).downcase.rjust(16, "0")
  end

end
