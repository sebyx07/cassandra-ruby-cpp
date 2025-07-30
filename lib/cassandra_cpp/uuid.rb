# frozen_string_literal: true

require 'securerandom'

module CassandraCpp
  # UUID utilities - will use native C++ UUID generation in final version
  class Uuid
    def self.generate
      SecureRandom.uuid
    end

    def self.time_uuid
      # Simple time-based UUID for POC
      # In real implementation, this would generate proper TimeUUID
      time_low = (Time.now.to_f * 1_000_000).to_i & 0xffffffff
      time_mid = (Time.now.to_i >> 32) & 0xffff
      time_hi = 0x1000 | ((Time.now.to_i >> 48) & 0x0fff)
      
      sprintf('%08x-%04x-%04x-%04x-%012x',
        time_low,
        time_mid, 
        time_hi,
        rand(0x10000),
        rand(0x1000000000000)
      )
    end

    def self.from_string(uuid_string)
      # Validate UUID format
      unless uuid_string.match?(/\A[\da-f]{8}-([\da-f]{4}-){3}[\da-f]{12}\z/i)
        raise ArgumentError, "Invalid UUID format: #{uuid_string}"
      end
      
      uuid_string.downcase
    end

    def self.valid?(uuid_string)
      !!(uuid_string =~ /\A[\da-f]{8}-([\da-f]{4}-){3}[\da-f]{12}\z/i)
    end
  end
end