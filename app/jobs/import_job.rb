class ImportJob < ApplicationJob
  queue_as :default

  def perform(*args)
    ImportService.new.start
  end
end
