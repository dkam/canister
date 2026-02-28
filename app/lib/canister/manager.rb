require 'singleton'
require 'rake'

class Canister::Manager
  include Singleton

  attr_reader :job_id
  attr_reader :status
  attr_reader :message
  attr_reader :logs

  attr_accessor :current
  attr_accessor :total

  def current=(value)
    @current = value
  end

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
        Rake::Task['db:drop'].invoke
        Rake::Task['db:create'].invoke
        Rake::Task['db:migrate'].invoke
      end

      Canister::Tasks::Import.new.start
    }

    idle
  end

  def export(job_id:, rake: true)
    return unless @status == :idle
    @job_id = job_id
    @status = :export
    @message = "Exporting..."
    @logs = []
    @rake = rake

    try {
      Canister::Tasks::Export.new.start
    }

    idle
  end

  def scan(job_id:, rake: true)
    return unless @status == :idle
    @job_id = job_id
    @status = :scan
    @message = "Scanning..."
    @logs = []
    @rake = rake

    @current = 0
    @total = 0
    Library.all.each do |library|
      glob_path = File.join(library.path, "**", "*.{zip,m4v,mp4,mov,wmv,mkv,avi,flv,webm}")
      scan_paths = Dir[glob_path]
      @total += scan_paths.count
      info("Starting scan of #{scan_paths.count} files in #{library.name} (#{library.path})")
      scan_paths.each { |path|
        @current += 1
        try {
          scan_task = Canister::Tasks::Scan.new(path: path, library: library)
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
    transcodes: true,
    rake: true
  )
    return unless @status == :idle
    @job_id = job_id
    @status = :generate
    @message = "Generating content..."
    @logs = []
    @rake = rake

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

  def clean(job_id:, rake: true)
    return unless @status == :idle
    @job_id = job_id
    @status = :clean
    @message = "Cleaning..."
    @logs = []
    @rake = rake

    try {
      # TODO: Clean up more and add progress
      Canister::Tasks::Clean.new.start
    }

    idle
  end

  def scrape(job_id:, scraper:, rake: true)
    return unless @status == :idle
    @job_id = job_id
    @status = :scrape
    @message = "Scraping..."
    @logs = []
    @rake = rake

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
      @rake = true
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
