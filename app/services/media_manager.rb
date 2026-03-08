require "singleton"
require "rake"

class MediaManager
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

      ImportService.new.start
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
      ExportService.new.start
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
      CleanService.new.start
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
