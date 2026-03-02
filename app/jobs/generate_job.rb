class GenerateJob < ApplicationJob
  queue_as :default

  before_enqueue do |job|
    @manager = Canister::Manager.instance
    raise('Operation already in progress') unless @manager.status == :idle
  end

  def perform(*args)
    @manager = Canister::Manager.instance
    @manager.generate(job_id: provider_job_id)
  end
end
