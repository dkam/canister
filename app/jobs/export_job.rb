class ExportJob < ApplicationJob
  queue_as :default

  def perform(*args)
    ExportService.new.start
  end
end
