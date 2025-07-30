# frozen_string_literal: true

module CassandraCpp
  # Session wrapper for native C++ implementation
  class Session
    def initialize(native_session, cluster)
      @native_session = native_session
      @cluster = cluster
      @prepared_statements = {}
    end

    def execute(query, *params)
      begin
        if params.empty?
          # Simple query without parameters
          result = @native_session.execute(query)
          Result.new(result)
        else
          # Use prepared statement for parameterized queries
          statement = prepare(query)
          statement.execute(*params)
        end
      rescue CassandraCpp::Error => e
        raise e
      rescue StandardError => e
        raise QueryError, "Query failed: #{e.message}"
      end
    end

    def prepare(query)
      @prepared_statements[query] ||= begin
        native_prepared = @native_session.prepare(query)
        PreparedStatement.new(native_prepared, query)
      end
    end

    # Create a new batch for atomic operations
    # @param type [Symbol] Batch type (:logged, :unlogged, :counter)
    # @return [Batch] New batch instance
    def batch(type = :logged)
      batch_type = case type
                   when :logged then CassandraCpp::BATCH_TYPE_LOGGED
                   when :unlogged then CassandraCpp::BATCH_TYPE_UNLOGGED
                   when :counter then CassandraCpp::BATCH_TYPE_COUNTER
                   else
                     raise ArgumentError, "Unknown batch type: #{type}"
                   end
      
      native_batch = @native_session.batch(batch_type)
      Batch.new(native_batch, self)
    end

    # Execute query asynchronously
    # @param query [String] CQL query to execute
    # @param params [Array] Parameters for prepared statements
    # @return [Future] Future object for async result handling
    def execute_async(query, *params)
      begin
        if params.empty?
          # Simple query without parameters - use native async
          native_future = @native_session.execute_async(query)
          Future.new(native_future)
        else
          # Use prepared statement for parameterized queries
          statement = prepare(query)
          statement.execute_async(*params)
        end
      rescue CassandraCpp::Error => e
        raise e
      rescue StandardError => e
        raise QueryError, "Async query failed: #{e.message}"
      end
    end

    # Prepare statement asynchronously
    # @param query [String] CQL query to prepare
    # @return [Future] Future object that will contain PreparedStatement
    def prepare_async(query)
      begin
        native_future = @native_session.prepare_async(query)
        
        # Create a mapped future that converts the result to PreparedStatement
        Future.new(native_future).map do |native_prepared|
          PreparedStatement.new(native_prepared, query)
        end
      rescue CassandraCpp::Error => e
        raise e
      rescue StandardError => e
        raise QueryError, "Async prepare failed: #{e.message}"
      end
    end

    def keyspace
      @native_session.keyspace
    end

    def close
      @native_session&.close
    end
  end
end