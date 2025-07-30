# frozen_string_literal: true

module CassandraCpp
  # Metrics tracking for session operations
  class SessionMetrics
    attr_reader :query_count, :prepared_statement_count, :error_count, 
                :total_query_time_ms, :batch_count, :async_query_count
    
    def initialize
      @query_count = 0
      @prepared_statement_count = 0
      @error_count = 0  
      @batch_count = 0
      @async_query_count = 0
      @total_query_time_ms = 0.0
      @query_times = []
      @mutex = Mutex.new
    end
    
    # Record a successful query execution
    # @param execution_time_ms [Float] Query execution time in milliseconds
    def record_query(execution_time_ms = 0.0)
      @mutex.synchronize do
        @query_count += 1
        @total_query_time_ms += execution_time_ms
        @query_times << execution_time_ms
        # Keep only last 1000 query times for percentile calculations
        @query_times.shift if @query_times.size > 1000
      end
    end
    
    # Record a prepared statement creation
    def record_prepared_statement
      @mutex.synchronize do
        @prepared_statement_count += 1
      end
    end
    
    # Record an error occurrence
    def record_error
      @mutex.synchronize do
        @error_count += 1
      end
    end
    
    # Record a batch operation
    def record_batch
      @mutex.synchronize do
        @batch_count += 1
      end
    end
    
    # Record an async query
    def record_async_query
      @mutex.synchronize do
        @async_query_count += 1
      end
    end
    
    # Get average query time in milliseconds
    # @return [Float] Average query time
    def average_query_time_ms
      return 0.0 if @query_count == 0
      @total_query_time_ms / @query_count
    end
    
    # Get query percentiles
    # @param percentile [Float] Percentile to calculate (e.g., 0.95 for 95th percentile)
    # @return [Float] Query time at the specified percentile
    def query_time_percentile(percentile)
      return 0.0 if @query_times.empty?
      
      sorted_times = @query_times.sort
      index = (percentile * (sorted_times.length - 1)).round
      sorted_times[index] || 0.0
    end
    
    # Get error rate as a percentage
    # @return [Float] Error rate percentage
    def error_rate
      total_operations = @query_count + @error_count
      return 0.0 if total_operations == 0
      (@error_count.to_f / total_operations * 100).round(2)
    end
    
    # Get comprehensive metrics summary
    # @return [Hash] Complete metrics summary
    def summary
      {
        queries: {
          total: @query_count,
          async: @async_query_count,
          batches: @batch_count,
          prepared_statements: @prepared_statement_count
        },
        performance: {
          total_time_ms: @total_query_time_ms.round(2),
          average_time_ms: average_query_time_ms.round(2),
          p50_ms: query_time_percentile(0.50).round(2),
          p95_ms: query_time_percentile(0.95).round(2),
          p99_ms: query_time_percentile(0.99).round(2)
        },
        errors: {
          count: @error_count,
          rate_percent: error_rate
        }
      }
    end
    
    # Reset all metrics
    def reset!
      @mutex.synchronize do
        @query_count = 0
        @prepared_statement_count = 0
        @error_count = 0
        @batch_count = 0
        @async_query_count = 0
        @total_query_time_ms = 0.0
        @query_times.clear
      end
    end
  end
end