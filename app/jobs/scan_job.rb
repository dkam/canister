class ScanJob < ApplicationJob
  queue_as :default

  def perform(library_id = nil)
    ScanService.run(library_id: library_id)
  end
end
