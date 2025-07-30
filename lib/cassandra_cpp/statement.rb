# frozen_string_literal: true

module CassandraCpp
  # Statement represents a bound prepared statement ready for execution
  # This class is typically not instantiated directly, but created through
  # PreparedStatement#bind
  #
  # @example
  #   prepared = session.prepare("INSERT INTO users (id, name) VALUES (?, ?)")
  #   statement = prepared.bind
  #   statement.bind(0, SecureRandom.uuid)
  #   statement.bind(1, "John Doe")
  #   result = statement.execute
  class Statement
    # This class wraps the native statement and is initialized internally
    # Users should not instantiate this class directly
    def initialize(native_statement)
      @native_statement = native_statement
      @bound_params = {}
    end
    
    # Bind a value to a parameter by index
    #
    # @param index [Integer] The parameter index (0-based)
    # @param value [Object] The value to bind
    # @return [self] Returns self for method chaining
    def bind(index, value)
      @bound_params[index] = value
      @native_statement.bind(index, value)
      self
    end
    
    # Execute the statement
    #
    # @return [Array<Hash>] The raw result rows
    def execute
      @native_statement.execute
    end
    
    # Get the bound parameters
    #
    # @return [Hash] A hash of index => value for bound parameters
    def bound_params
      @bound_params.dup
    end
  end
end