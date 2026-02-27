class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:check]

  def check
    render json: {status: "ok", timestamp: Time.current}, status: :ok
  end
end
