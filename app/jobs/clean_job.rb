class CleanJob < ApplicationJob
  queue_as :default

  def perform(*args)
    CleanService.new.start
  end
end
