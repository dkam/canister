require "singleton"
require "rake"

class Canister::Manager
  include Singleton

  attr_reader :job_id
  attr_reader :status
  attr_reader :message
  attr_reader :logs

  attr_accessor :current
  attr_accessor :total

  attr_writer :current

  def initialize
    @logs = []
    idle
  end

  def import(job_id:, rake: true)
    return unless @status == :idle
    @job_id = job_id
    @status = :import
    @message = "Importing..."
    @logs = []
    @rake = rake

    try {
      if !rake
        Rails.application.load_tasks
        Rake::Task["db:drop"].invoke
        Rake::Task["db:create"].invoke
        Rake::Task["db:migrate"].invoke
      end

      Canister::Tasks::Import.new.start
    }

    idle
  end

  def export(job_id:)
    return unless @status == :idle
    @job_id = job_id
    @status = :export
    @message = "Exporting..."
    @logs = []

    try {
      Canister::Tasks::Export.new.start
    }

    idle
  end

  def scan(job_id:, library_id: nil)
    return unless @status == :idle
    @job_id = job_id
    @status = :scan
    @message = "Scanning..."
    @logs = []

    @current = 0
    @total = 0
    libraries = library_id ? Library.where(id: library_id) : Library.all
    libraries.each do |library|
      scan_paths = library.backend.list_files(extensions: Canister::MEDIA_EXTENSIONS)
      @total += scan_paths.count
      info("Starting scan of #{scan_paths.count} files in #{library.name} (#{library.path})")
      scan_paths.each { |relative_path|
        @current += 1
        try {
          scan_task = Canister::Tasks::Scan.new(path: relative_path, library: library)
          scan_task.start
        }
      }
    end

    idle
  end

  def generate(
    job_id:,
    sprites: true,
    previews: true,
    markers: true,
    transcodes: true
  )
    return unless @status == :idle
    @job_id = job_id
    @status = :generate
    @message = "Generating content..."
    @logs = []

    @total = Scene.count
    Scene.all.each { |scene|
      @current += 1

      if transcodes
        try {
          transcode_task = Canister::Tasks::GenerateTranscode.new(scene: scene)
          transcode_task.start
        }
      end

      if sprites
        try {
          sprite_task = Canister::Tasks::GenerateSprite.new(scene: scene)
          sprite_task.start
        }
      end

      if previews
        try {
          preview_task = Canister::Tasks::GeneratePreview.new(scene: scene)
          preview_task.start
        }
      end

      if markers
        try {
          marker_task = Canister::Tasks::GenerateMarkers.new(scene: scene)
          marker_task.start
        }
      end
    }

    idle
  end

  def clean(job_id:)
    return unless @status == :idle
    @job_id = job_id
    @status = :clean
    @message = "Cleaning..."
    @logs = []

    try {
      # TODO: Clean up more and add progress
      Canister::Tasks::Clean.new.start
    }

    idle
  end

  def scrape(job_id:, scraper:)
    return unless @status == :idle
    @job_id = job_id
    @status = :scrape
    @message = "Scraping..."
    @logs = []

    try {
      # TODO: Clean up more and add progress
      scraper.start
    }

    idle
  end

  def progress
    return 0 if @total == 0
    (@current / @total.to_f) * 100
  end

  # Logging

  def info(message)
    Rails.logger.tagged(@job_id) { Rails.logger.info(message) }
    add_log(type: :info, message: message)
  end

  def debug(message)
    Rails.logger.tagged(@job_id) { Rails.logger.debug(message) }
    add_log(type: :debug, message: message)
  end

  def warn(message)
    Rails.logger.tagged(@job_id) { Rails.logger.warn(message) }
    add_log(type: :warn, message: message)
  end

  def error(message)
    Rails.logger.tagged(@job_id) { Rails.logger.error(message) }
    add_log(type: :error, message: message)
  end

  private

  def idle
    @status = :idle
    @message = "Waiting..."
    @current = 0
    @total = 0
  end

  def add_log(message)
    @logs.unshift(message)
  end

  def try
    yield
  rescue ScriptError => e
    error("#{e.inspect} --> #{e.backtrace.first}")
  rescue => e
    error("#{e.inspect} --> #{e.backtrace.first}")
  rescue Exception => e
    idle
    raise e
  end
end
