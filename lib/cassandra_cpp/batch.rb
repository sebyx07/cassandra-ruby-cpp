# frozen_string_literal: true

module CassandraCpp
  # Ruby wrapper for native batch operations
  class Batch
    def initialize(native_batch, session)
      @native_batch = native_batch
      @session = session
    end

    # Add a statement to the batch
    # @param statement_or_query [String, PreparedStatement] Query string or prepared statement
    # @param params [Array] Parameters to bind (only used with query strings)
    def add(statement_or_query, params = nil)
      case statement_or_query
      when String
        @native_batch.add_statement(statement_or_query, params)
      when PreparedStatement
        # Bind the prepared statement and add to batch
        bound_statement = statement_or_query.bind(*params) if params
        bound_statement ||= statement_or_query.bind
        @native_batch.add_statement(bound_statement, nil)
      else
        # Assume it's already a bound statement
        @native_batch.add_statement(statement_or_query, nil)
      end
      
      self
    end

    # Set the consistency level for the batch
    # @param consistency [Integer] Consistency level constant
    def consistency=(consistency)
      @native_batch.consistency = consistency
      self
    end

    # Execute the batch
    # @return [Result] Batch execution result (typically empty)
    def execute
      rows = @native_batch.execute
      Result.new(rows)
    end

    # Batch builder methods for fluent interface
    
    # Add a statement using method chaining
    # @param statement_or_query [String, PreparedStatement] Query string or prepared statement
    # @param params [Array] Parameters to bind
    def statement(statement_or_query, *params)
      add(statement_or_query, params.empty? ? nil : params)
    end

    # Set consistency using method chaining
    # @param level [Integer] Consistency level
    def with_consistency(level)
      self.consistency = level
      self
    end
  end
end