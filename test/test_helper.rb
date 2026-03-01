ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

class ActiveSupport::TestCase
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

module FixturesTestHelper
  extend ActiveSupport::Concern

  class_methods do
    def identify(label, column_type = :integer)
      if label.to_s.end_with?("_uuid")
        column_type = :uuid
        label = label.to_s.delete_suffix("_uuid")
      end

      return super(label, column_type) unless column_type.in?([:uuid, :string])
      generate_fixture_uuid(label)
    end

    private

    def generate_fixture_uuid(label)
      # Generate deterministic UUIDv7 for fixtures that sorts by fixture ID
      # This allows .first/.last to work as expected in tests
      fixture_int = Zlib.crc32("fixtures/#{label}") % (2**30 - 1)

      # Translate the deterministic order into times in the past
      base_time = Time.utc(2024, 1, 1, 0, 0, 0)
      timestamp = base_time + (fixture_int / 1000.0)

      uuid_v7_with_timestamp(timestamp, label)
    end

    def uuid_v7_with_timestamp(time, seed_string)
      # Generate UUIDv7 with custom timestamp and deterministic random bits
      time_ms = time.to_f * 1000
      timestamp_ms = time_ms.to_i

      bytes = []
      bytes[0] = (timestamp_ms >> 40) & 0xff
      bytes[1] = (timestamp_ms >> 32) & 0xff
      bytes[2] = (timestamp_ms >> 24) & 0xff
      bytes[3] = (timestamp_ms >> 16) & 0xff
      bytes[4] = (timestamp_ms >> 8) & 0xff
      bytes[5] = timestamp_ms & 0xff

      frac_ms = time_ms - timestamp_ms
      sub_ms_precision = (frac_ms * 4096).to_i & 0xfff

      hash = Digest::MD5.hexdigest(seed_string)

      bytes[6] = ((sub_ms_precision >> 8) & 0x0f) | 0x70
      bytes[7] = sub_ms_precision & 0xff

      rand_b = hash[3...19].to_i(16) & ((2**62) - 1)
      bytes[8] = ((rand_b >> 56) & 0x3f) | 0x80
      bytes[9] = (rand_b >> 48) & 0xff
      bytes[10] = (rand_b >> 40) & 0xff
      bytes[11] = (rand_b >> 32) & 0xff
      bytes[12] = (rand_b >> 24) & 0xff
      bytes[13] = (rand_b >> 16) & 0xff
      bytes[14] = (rand_b >> 8) & 0xff
      bytes[15] = rand_b & 0xff

      uuid = "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % bytes
      ActiveRecord::Type::Uuid.hex_to_base36(uuid.delete("-"))
    end
  end
end

ActiveSupport.on_load(:active_record_fixture_set) do
  prepend(FixturesTestHelper)
end
