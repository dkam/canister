class ExportJob < ApplicationJob
  queue_as :default

  before_enqueue do |job|
    @manager = MediaManager.instance
    raise('Operation already in progress') unless @manager.status == :idle
  end

  def perform(*args)
    @manager = MediaManager.instance
    @manager.export(job_id: provider_job_id)
  end
end
