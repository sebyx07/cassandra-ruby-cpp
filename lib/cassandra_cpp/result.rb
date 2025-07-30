# frozen_string_literal: true

module CassandraCpp
  # Result set wrapper for native C++ implementation
  class Result
    include Enumerable

    def initialize(native_result)
      @native_result = native_result
    end

    def each
      return enum_for(:each) unless block_given?
      
      # Native extension returns array of hashes directly
      @native_result.each do |row|
        yield row
      end
    end

    def size
      @native_result.size
    end
    alias count size
    alias length size

    def empty?
      size == 0
    end

    def first
      @native_result.first
    end

    def last
      @native_result.last
    end

    def to_a
      @native_result
    end

    def columns
      # Get column names from the first row if available
      @columns ||= first&.keys || []
    end
  end
end