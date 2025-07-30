# frozen_string_literal: true

module CassandraCpp
  # Future class for handling asynchronous operations
  # 
  # Provides a Ruby-friendly interface to Cassandra's async operations
  # with support for callbacks, promise chaining, and timeouts.
  #
  # @example Basic usage
  #   future = session.execute_async("SELECT * FROM users")
  #   result = future.value  # Blocks until complete
  #
  # @example With callbacks
  #   future = session.execute_async("SELECT * FROM users")
  #   future.then { |result| puts "Got #{result.size} rows" }
  #   future.rescue { |error| puts "Error: #{error}" }
  #   future.execute_callbacks
  #
  # @example Promise chaining
  #   session.execute_async("SELECT * FROM users")
  #     .then { |result| process_users(result) }
  #     .rescue { |error| handle_error(error) }
  #     .execute_callbacks
  class Future
    # @private
    # Initialize with native future object
    def initialize(native_future)
      @native_future = native_future
      @success_callbacks = []
      @error_callbacks = []
    end

    # Register a success callback
    # 
    # @param block [Proc] Callback to execute on success
    # @return [Future] self for chaining
    # @example
    #   future.then { |result| puts "Success: #{result}" }
    def then(&block)
      raise ArgumentError, 'No block given' unless block_given?
      
      @success_callbacks << block
      @native_future&.then(&block)
      self
    end

    # Register an error callback
    # 
    # @param block [Proc] Callback to execute on error
    # @return [Future] self for chaining
    # @example
    #   future.rescue { |error| puts "Error: #{error}" }
    def rescue(&block)
      raise ArgumentError, 'No block given' unless block_given?
      
      @error_callbacks << block
      @native_future&.rescue(&block)
      self
    end

    # Get the result, blocking until completion
    # 
    # @param timeout [Float, nil] Timeout in seconds, nil for no timeout
    # @return [Array<Hash>] Query results
    # @raise [CassandraCpp::Error] If the operation failed
    # @raise [CassandraCpp::Error] If timeout exceeded
    # @example
    #   result = future.value(5.0)  # Wait up to 5 seconds
    def value(timeout = nil)
      return @native_future.value(timeout) if @native_future
      
      # For custom futures without native implementation, subclasses should override
      raise NotImplementedError, "Subclass must implement value method"
    end

    # Check if the future is ready (completed)
    # 
    # @return [Boolean] true if ready, false if still executing
    # @example
    #   puts "Still running..." unless future.ready?
    def ready?
      return @native_future.ready? if @native_future
      
      # For custom futures, subclasses should override
      true  # Default to ready for custom implementations
    end

    # Execute registered callbacks asynchronously
    # 
    # This method starts background thread execution of callbacks.
    # The callbacks will be executed when the future completes.
    # 
    # @return [Future] self for chaining
    # @example
    #   future.then { |result| puts result }
    #         .rescue { |error| puts error }
    #         .execute_callbacks
    def execute_callbacks
      return (@native_future.execute_callbacks && self) if @native_future
      
      # For custom futures, subclasses should override or handle callbacks themselves
      self
    end

    # Wait for completion and return self
    # 
    # This is a convenience method that blocks until the future
    # completes but returns the future object rather than the result.
    # 
    # @param timeout [Float, nil] Timeout in seconds
    # @return [Future] self
    # @example
    #   future.wait.then { |result| puts result }
    def wait(timeout = nil)
      @native_future.value(timeout)
      self
    rescue Error
      # Ignore errors in wait - they'll be handled by callbacks
      self
    end

    # Create a new Future that will execute the given block with this future's result
    # 
    # @param block [Proc] Block to execute with the result
    # @return [Future] New future with the transformed result
    # @example
    #   users_future = session.execute_async("SELECT * FROM users")
    #   count_future = users_future.map { |users| users.size }
    def map(&block)
      raise ArgumentError, 'No block given' unless block_given?
      
      # Create a new "virtual" future that will contain the mapped result
      mapped_future = MappedFuture.new(self, block)
      mapped_future
    end

    # Combine this future with another future
    # 
    # @param other_future [Future] Another future to combine with
    # @return [Future] New future that completes when both complete
    # @example
    #   users_future = session.execute_async("SELECT * FROM users")
    #   posts_future = session.execute_async("SELECT * FROM posts") 
    #   combined = users_future.zip(posts_future)
    #   combined.then { |users, posts| puts "#{users.size} users, #{posts.size} posts" }
    def zip(other_future)
      CombinedFuture.new(self, other_future)
    end

    # @private
    # Access to the native future (for internal use)
    attr_reader :native_future

    private

    # Internal class for mapped futures
    class MappedFuture < Future
      def initialize(source_future, transform_block)
        @native_future = nil  # No native future for mapped futures
        @source_future = source_future
        @transform_block = transform_block
        @success_callbacks = []
        @error_callbacks = []
      end

      def value(timeout = nil)
        source_result = @source_future.value(timeout)
        @transform_block.call(source_result)
      end

      def ready?
        @source_future.ready?
      end

      def execute_callbacks
        @source_future.then do |result|
          begin
            transformed_result = @transform_block.call(result)
            @success_callbacks.each { |callback| callback.call(transformed_result) }
          rescue => e
            @error_callbacks.each { |callback| callback.call(e.message) }
          end
        end

        @source_future.rescue do |error|
          @error_callbacks.each { |callback| callback.call(error) }
        end

        @source_future.execute_callbacks
        self
      end
    end

    # Internal class for combined futures
    class CombinedFuture < Future
      def initialize(future1, future2)
        @native_future = nil  # No native future for combined futures
        @future1 = future1
        @future2 = future2
        @success_callbacks = []
        @error_callbacks = []
      end

      def value(timeout = nil)
        # Wait for both futures to complete
        result1 = @future1.value(timeout)
        result2 = @future2.value(timeout)
        [result1, result2]
      end

      def ready?
        @future1.ready? && @future2.ready?
      end

      def execute_callbacks
        results = [nil, nil]
        errors = []
        completed = 0

        check_completion = proc do
          if completed == 2
            if errors.empty?
              @success_callbacks.each { |callback| callback.call(*results) }
            else
              error_msg = errors.join('; ')
              @error_callbacks.each { |callback| callback.call(error_msg) }
            end
          end
        end

        @future1.then do |result|
          results[0] = result
          completed += 1
          check_completion.call
        end

        @future1.rescue do |error|
          errors << "Future1: #{error}"
          completed += 1
          check_completion.call
        end

        @future2.then do |result|
          results[1] = result
          completed += 1
          check_completion.call
        end

        @future2.rescue do |error|
          errors << "Future2: #{error}"
          completed += 1
          check_completion.call
        end

        @future1.execute_callbacks
        @future2.execute_callbacks
        self
      end
    end
  end
end