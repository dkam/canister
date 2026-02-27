# Call scopes directly from your URL params:
#
#     @products = Product.filter(params.slice(:status, :location, :starts_with))
module Filterable
  extend ActiveSupport::Concern

  included do
    def self.filter(params)
      params = params.stringify_keys
      results = all
      params.each do |key, value|
        if value.present? || (value.is_a?(TrueClass) || value.is_a?(FalseClass))
          value = value.split(",") if value.is_a? String
          results = results.public_send(key, value)
        end
      end
      results
    end
  end
end
