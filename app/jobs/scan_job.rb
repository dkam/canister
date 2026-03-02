class ScanJob < ApplicationJob
  queue_as :default

  before_enqueue do |job|
    @manager = Canister::Manager.instance
    raise('Operation already in progress') unless @manager.status == :idle
  end

  def perform(library_id = nil)
    @manager = Canister::Manager.instance
    @manager.scan(job_id: provider_job_id, library_id: library_id)
  end
end
