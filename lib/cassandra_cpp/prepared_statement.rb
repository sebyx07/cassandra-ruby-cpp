# frozen_string_literal: true

module CassandraCpp
  # PreparedStatement represents a prepared CQL statement that can be executed multiple times
  # with different parameters. This provides better performance than executing raw queries
  # as the statement is parsed only once by Cassandra.
  #
  # @example Basic usage
  #   statement = session.prepare("INSERT INTO users (id, name, email) VALUES (?, ?, ?)")
  #   statement.execute(SecureRandom.uuid, "John Doe", "john@example.com")
  #
  # @example With named parameters (future enhancement)
  #   statement = session.prepare("INSERT INTO users (id, name, email) VALUES (:id, :name, :email)")
  #   statement.execute(id: SecureRandom.uuid, name: "John Doe", email: "john@example.com")
  class PreparedStatement
    attr_reader :query
    
    # Initialize a new PreparedStatement
    # This is typically called internally by Session#prepare
    #
    # @param native_prepared [NativePreparedStatement] The native prepared statement object
    # @param query [String] The original CQL query
    def initialize(native_prepared, query)
      @native_prepared = native_prepared
      @query = query
      @param_count = count_parameters(query)
    end
    
    # Execute the prepared statement with the given parameters
    #
    # @param args [Array] The parameters to bind to the statement
    # @return [Result] The query result
    # @raise [CassandraCpp::Error] if parameter count doesn't match or execution fails
    def execute(*args)
      validate_parameter_count(args.length)
      
      # Create a bound statement
      statement = @native_prepared.bind
      
      # Bind parameters
      args.each_with_index do |value, index|
        statement.bind(index, value)
      end
      
      # Execute and wrap result
      rows = statement.execute
      Result.new(rows)
    end

    # Execute the prepared statement asynchronously with the given parameters
    #
    # @param args [Array] The parameters to bind to the statement
    # @return [Future] Future object for async result handling
    # @raise [CassandraCpp::Error] if parameter count doesn't match or execution fails
    def execute_async(*args)
      validate_parameter_count(args.length)
      
      # Create a bound statement
      statement = @native_prepared.bind
      
      # Bind parameters
      args.each_with_index do |value, index|
        statement.bind(index, value)
      end
      
      # Execute asynchronously and wrap in Future
      native_future = statement.execute_async
      
      # Create a mapped future that converts result rows to Result object
      Future.new(native_future).map { |rows| Result.new(rows) }
    end
    
    # Execute the prepared statement with named parameters
    # This is a convenience method that will be implemented in the future
    #
    # @param params [Hash] Named parameters
    # @return [Result] The query result
    # @raise [NotImplementedError] This feature is not yet implemented
    def execute_with_params(params)
      raise NotImplementedError, "Named parameters are not yet supported"
    end
    
    # Get the number of parameters in the prepared statement
    #
    # @return [Integer] The number of parameters
    def param_count
      @param_count
    end
    
    # Check if the statement has parameters
    #
    # @return [Boolean] true if the statement has parameters
    def has_params?
      @param_count > 0
    end
    
    private
    
    # Count the number of ? parameters in the query
    #
    # @param query [String] The CQL query
    # @return [Integer] The number of parameters
    def count_parameters(query)
      # Simple count of ? not inside quotes
      # This is a basic implementation and might need improvement
      # for complex queries with strings containing ?
      in_string = false
      quote_char = nil
      count = 0
      
      query.each_char.with_index do |char, i|
        if !in_string && (char == '"' || char == "'")
          in_string = true
          quote_char = char
        elsif in_string && char == quote_char && (i == 0 || query[i-1] != '\\')
          in_string = false
          quote_char = nil
        elsif !in_string && char == '?'
          count += 1
        end
      end
      
      count
    end
    
    # Validate that the correct number of parameters were provided
    #
    # @param provided_count [Integer] The number of parameters provided
    # @raise [ArgumentError] if the parameter count doesn't match
    def validate_parameter_count(provided_count)
      if provided_count != @param_count
        raise ArgumentError, "Wrong number of parameters: expected #{@param_count}, got #{provided_count}"
      end
    end
  end
end