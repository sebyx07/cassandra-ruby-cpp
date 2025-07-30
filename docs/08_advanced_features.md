# Advanced Features Guide

This guide covers advanced features of Cassandra-CPP that enable sophisticated use cases, including asynchronous operations, streaming, custom type converters, and integration patterns.

## Table of Contents

- [Asynchronous Operations](#asynchronous-operations)
- [Streaming Large Result Sets](#streaming-large-result-sets)
- [Complex Query Patterns](#complex-query-patterns)
- [Custom Type Converters](#custom-type-converters)
- [Event Hooks and Callbacks](#event-hooks-and-callbacks)
- [Connection Management](#connection-management)
- [Security Features](#security-features)
- [Integration Patterns](#integration-patterns)
- [Advanced Monitoring](#advanced-monitoring)
- [Custom Extensions](#custom-extensions)

## Asynchronous Operations

### Basic Async Queries

```ruby
# Enable async support
CassandraCpp.configure do |config|
  config.enable_async = true
  config.async_thread_pool_size = 10
end

class AsyncUser < CassandraCpp::Model
  # Async query execution
  def self.find_async(id)
    CassandraCpp::Future.new do
      connection_pool.with_connection do |conn|
        conn.execute("SELECT * FROM users WHERE id = ?", id)
      end
    end
  end
  
  # Async operations with callbacks
  def self.create_async(attributes, &callback)
    future = CassandraCpp::Future.new do
      create!(attributes)
    end
    
    if callback
      future.on_success(&callback)
      future.on_failure { |error| puts "Creation failed: #{error}" }
    end
    
    future
  end
  
  # Multiple async operations
  def self.find_multiple_async(ids)
    futures = ids.map do |id|
      find_async(id)
    end
    
    # Combine results when all complete
    CassandraCpp::Future.all(futures).then do |users|
      users.compact
    end
  end
end

# Usage examples
# Fire and forget
AsyncUser.create_async(name: 'John', email: 'john@example.com')

# With callback
AsyncUser.create_async(name: 'Jane', email: 'jane@example.com') do |user|
  puts "User created: #{user.id}"
end

# Wait for result
future = AsyncUser.find_async(user_id)
user = future.value  # Blocks until complete

# Parallel execution
user_futures = AsyncUser.find_multiple_async(['id1', 'id2', 'id3'])
users = user_futures.value
```

### Advanced Async Patterns

```ruby
class AsyncQueryProcessor
  def initialize(concurrency: 10)
    @semaphore = CassandraCpp::Semaphore.new(concurrency)
    @results = Concurrent::Array.new
  end
  
  def process_async(queries)
    futures = queries.map do |query|
      @semaphore.acquire
      
      CassandraCpp::Future.new do
        begin
          result = execute_query(query)
          @results << result
          result
        ensure
          @semaphore.release
        end
      end
    end
    
    # Wait for all to complete
    CassandraCpp::Future.all(futures)
  end
  
  def process_with_rate_limit(queries, rate_limit: 100)
    rate_limiter = CassandraCpp::RateLimiter.new(rate_limit)
    
    queries.each_slice(10) do |batch|
      rate_limiter.acquire
      
      batch_futures = batch.map do |query|
        CassandraCpp::Future.new { execute_query(query) }
      end
      
      CassandraCpp::Future.all(batch_futures).value
    end
  end
  
  private
  
  def execute_query(query)
    # Query execution logic
  end
end

# Circuit breaker pattern for async operations
class AsyncCircuitBreaker
  def initialize(failure_threshold: 5, timeout: 60)
    @failure_threshold = failure_threshold
    @timeout = timeout
    @failure_count = 0
    @last_failure = nil
    @state = :closed  # :closed, :open, :half_open
  end
  
  def execute_async(&block)
    if circuit_open?
      return CassandraCpp::Future.failed(
        CassandraCpp::CircuitBreakerOpenError.new
      )
    end
    
    future = CassandraCpp::Future.new(&block)
    
    future.on_success { on_success }
    future.on_failure { |error| on_failure(error) }
    
    future
  end
  
  private
  
  def circuit_open?
    @state == :open && (Time.now - @last_failure) < @timeout
  end
  
  def on_success
    @failure_count = 0
    @state = :closed
  end
  
  def on_failure(error)
    @failure_count += 1
    @last_failure = Time.now
    
    if @failure_count >= @failure_threshold
      @state = :open
    end
  end
end
```

### Async Batch Operations

```ruby
class AsyncBatchProcessor
  def initialize(batch_size: 100, max_concurrent: 5)
    @batch_size = batch_size
    @max_concurrent = max_concurrent
    @executor = Concurrent::ThreadPoolExecutor.new(
      min_threads: 2,
      max_threads: max_concurrent,
      max_queue: 100
    )
  end
  
  def process_records_async(records)
    record_batches = records.each_slice(@batch_size).to_a
    
    # Process batches concurrently
    futures = record_batches.map do |batch|
      Concurrent::Future.execute(executor: @executor) do
        process_batch(batch)
      end
    end
    
    # Collect results
    results = futures.map(&:value!)
    results.flatten
  end
  
  def process_with_pipeline(records)
    # Create processing pipeline
    pipeline = CassandraCpp::Pipeline.new
    
    # Stage 1: Validation
    validation_stage = pipeline.add_stage(:validate) do |record|
      validate_record(record)
    end
    
    # Stage 2: Transform
    transform_stage = pipeline.add_stage(:transform) do |record|
      transform_record(record)
    end
    
    # Stage 3: Persist
    persist_stage = pipeline.add_stage(:persist) do |record|
      User.create!(record)
    end
    
    # Process records through pipeline
    pipeline.process_async(records)
  end
  
  private
  
  def process_batch(batch)
    User.batch do
      batch.each { |record| User.create!(record) }
    end
  end
end
```

## Streaming Large Result Sets

### Basic Streaming

```ruby
class StreamingQuery
  def self.stream_users(batch_size: 1000)
    last_token = nil
    
    loop do
      query = User.limit(batch_size)
      query = query.where("token(id) > ?", last_token) if last_token
      
      batch = query.to_a
      break if batch.empty?
      
      # Yield each record
      batch.each { |user| yield user }
      
      # Update pagination token
      last_token = batch.last.token(:id)
    end
  end
  
  def self.stream_with_backpressure(query, batch_size: 1000, max_buffer: 10)
    buffer = Queue.new
    finished = false
    
    # Producer thread
    producer = Thread.new do
      begin
        stream_users(batch_size: batch_size) do |user|
          # Block if buffer is full (backpressure)
          while buffer.size >= max_buffer
            sleep 0.001
          end
          buffer << user
        end
      ensure
        buffer << :finished
        finished = true
      end
    end
    
    # Consumer yields from buffer
    until finished && buffer.empty?
      if (user = buffer.pop(true) rescue nil)
        break if user == :finished
        yield user
      else
        sleep 0.001
      end
    end
    
    producer.join
  end
end

# Usage
StreamingQuery.stream_users(batch_size: 5000) do |user|
  process_user(user)
  
  # Memory management - process and release
  GC.start if rand(1000) == 0
end
```

### Advanced Streaming Patterns

```ruby
class AdvancedStreaming
  include Enumerable
  
  def initialize(query, batch_size: 1000)
    @query = query
    @batch_size = batch_size
  end
  
  # Make it enumerable
  def each
    return enum_for(:each) unless block_given?
    
    @query.find_each(batch_size: @batch_size) do |record|
      yield record
    end
  end
  
  # Streaming with transformation
  def map_stream(&block)
    Enumerator.new do |yielder|
      each do |record|
        yielder << block.call(record)
      end
    end
  end
  
  # Streaming with filtering
  def filter_stream(&block)
    Enumerator.new do |yielder|
      each do |record|
        yielder << record if block.call(record)
      end
    end
  end
  
  # Parallel streaming
  def parallel_each(worker_count: 4, &block)
    work_queue = Queue.new
    workers = []
    
    # Start worker threads
    worker_count.times do
      workers << Thread.new do
        while (record = work_queue.pop) != :finished
          block.call(record)
        end
      end
    end
    
    # Feed work queue
    each { |record| work_queue << record }
    
    # Signal completion
    worker_count.times { work_queue << :finished }
    
    # Wait for workers
    workers.each(&:join)
  end
end

# Usage
stream = AdvancedStreaming.new(User.where(status: 'active'))

# Lazy processing
processed = stream
  .filter_stream { |user| user.age > 18 }
  .map_stream { |user| user.email }
  .first(1000)

# Parallel processing
stream.parallel_each(worker_count: 8) do |user|
  expensive_processing(user)
end
```

### Memory-Efficient Streaming

```ruby
class MemoryEfficientStream
  def initialize(query, options = {})
    @query = query
    @batch_size = options[:batch_size] || 1000
    @prefetch_size = options[:prefetch_size] || 2
    @transform_proc = options[:transform]
  end
  
  def stream(&block)
    return enum_for(:stream) unless block_given?
    
    buffer = create_ring_buffer(@prefetch_size)
    producer_thread = start_producer(buffer)
    
    begin
      while (batch = buffer.pop) != :finished
        process_batch(batch, &block)
        
        # Explicit memory cleanup
        batch.clear
        GC.start if should_gc?
      end
    ensure
      producer_thread.join
    end
  end
  
  private
  
  def create_ring_buffer(size)
    # Thread-safe ring buffer implementation
    CassandraCpp::RingBuffer.new(size)
  end
  
  def start_producer(buffer)
    Thread.new do
      begin
        last_token = nil
        
        loop do
          batch_query = @query.limit(@batch_size)
          batch_query = batch_query.where("token(id) > ?", last_token) if last_token
          
          batch = batch_query.to_a
          break if batch.empty?
          
          # Transform batch if needed
          if @transform_proc
            batch.map!(&@transform_proc)
          end
          
          # Block if buffer is full
          buffer.push(batch)
          
          last_token = batch.last.token(:id)
        end
      rescue => error
        buffer.push_error(error)
      ensure
        buffer.push(:finished)
      end
    end
  end
  
  def process_batch(batch, &block)
    batch.each(&block)
  end
  
  def should_gc?
    # GC every 10 batches
    (@batch_count += 1) % 10 == 0
  end
end

# Usage with memory monitoring
stream = MemoryEfficientStream.new(
  User.where(created_at: 1.year.ago..Time.now),
  batch_size: 2000,
  prefetch_size: 3,
  transform: ->(user) { { id: user.id, email: user.email } }
)

initial_memory = `ps -o rss= -p #{Process.pid}`.strip.to_i
processed_count = 0

stream.stream do |user_data|
  process_user_data(user_data)
  processed_count += 1
  
  if processed_count % 10000 == 0
    current_memory = `ps -o rss= -p #{Process.pid}`.strip.to_i
    puts "Processed #{processed_count}, Memory: #{current_memory - initial_memory}KB"
  end
end
```

## Complex Query Patterns

### Dynamic Query Building

```ruby
class DynamicQueryBuilder
  def initialize(model)
    @model = model
    @conditions = []
    @joins = []
    @orders = []
    @limits = {}
  end
  
  def where(conditions)
    case conditions
    when Hash
      conditions.each do |key, value|
        add_condition(key, value)
      end
    when String
      @conditions << conditions
    end
    self
  end
  
  def join(association, type: :inner)
    @joins << { association: association, type: type }
    self
  end
  
  def order(field, direction = :asc)
    @orders << { field: field, direction: direction }
    self
  end
  
  def limit(count)
    @limits[:count] = count
    self
  end
  
  def build
    query = @model
    
    # Apply conditions
    @conditions.each do |condition|
      query = query.where(condition)
    end
    
    # Apply joins (if supported)
    @joins.each do |join_spec|
      query = apply_join(query, join_spec)
    end
    
    # Apply ordering
    @orders.each do |order_spec|
      query = query.order(order_spec[:field] => order_spec[:direction])
    end
    
    # Apply limits
    query = query.limit(@limits[:count]) if @limits[:count]
    
    query
  end
  
  private
  
  def add_condition(key, value)
    case value
    when Array
      @conditions << "#{key} IN (#{value.map { '?' }.join(', ')})"
    when Range
      @conditions << "#{key} >= ? AND #{key} <= ?"
    when nil
      @conditions << "#{key} IS NULL"
    else
      @conditions << "#{key} = ?"
    end
  end
  
  def apply_join(query, join_spec)
    # Implement join logic based on associations
    # This would depend on your specific association implementation
    query
  end
end

# Usage
builder = DynamicQueryBuilder.new(User)
  .where(status: 'active')
  .where(age: 18..65)
  .where('created_at > ?')
  .order(:name, :asc)
  .limit(100)

users = builder.build.to_a
```

### Query Composition

```ruby
module QueryComposition
  def self.included(base)
    base.extend(ClassMethods)
  end
  
  module ClassMethods
    def scope(name, body)
      define_singleton_method(name, body)
    end
    
    def compose(*scopes)
      scopes.reduce(self) { |query, scope| query.send(scope) }
    end
  end
end

class User < CassandraCpp::Model
  include QueryComposition
  
  # Define reusable scopes
  scope :active, -> { where(status: 'active') }
  scope :adults, -> { where('age >= ?', 18) }
  scope :recent, ->(days = 30) { where('created_at > ?', days.days.ago) }
  scope :in_country, ->(country) { where(country: country) }
  scope :with_email, -> { where.not(email: nil) }
  
  # Complex composed queries
  def self.active_adults_in_country(country)
    compose(:active, :adults).in_country(country)
  end
  
  def self.marketing_targets(country)
    active
      .adults
      .with_email
      .in_country(country)
      .recent(90)
  end
end

# Usage
users = User.marketing_targets('US').limit(1000)

# Dynamic composition
scopes = [:active, :adults]
scopes << :recent if params[:recent_only]
users = User.compose(*scopes)
```

### Subqueries and CTEs

```ruby
class SubqueryBuilder
  def self.users_with_recent_orders
    # Subquery to find users with orders in last 30 days
    recent_order_users = Order
      .select(:user_id)
      .where('created_at > ?', 30.days.ago)
      .distinct
    
    # Main query using subquery
    User.where(id: recent_order_users)
  end
  
  def self.top_spenders(limit = 100)
    # Use raw CQL for complex aggregation
    User.execute(<<-CQL, limit)
      SELECT u.*, spending.total_spent
      FROM users u
      JOIN (
        SELECT user_id, sum(total) as total_spent
        FROM orders
        WHERE created_at > ?
        GROUP BY user_id
        ORDER BY total_spent DESC
        LIMIT ?
      ) spending ON u.id = spending.user_id
    CQL, 1.year.ago, limit
  end
  
  def self.cohort_analysis(start_date, end_date)
    # Complex analytical query
    execute(<<-CQL)
      WITH user_cohorts AS (
        SELECT 
          date_trunc('month', created_at) as cohort_month,
          id as user_id
        FROM users
        WHERE created_at BETWEEN ? AND ?
      ),
      user_activities AS (
        SELECT 
          uc.cohort_month,
          uc.user_id,
          date_trunc('month', o.created_at) as activity_month,
          count(*) as orders_count
        FROM user_cohorts uc
        JOIN orders o ON uc.user_id = o.user_id
        GROUP BY uc.cohort_month, uc.user_id, activity_month
      )
      SELECT 
        cohort_month,
        activity_month,
        count(distinct user_id) as active_users,
        sum(orders_count) as total_orders
      FROM user_activities
      GROUP BY cohort_month, activity_month
      ORDER BY cohort_month, activity_month
    CQL, start_date, end_date
  end
end
```

## Custom Type Converters

### Creating Custom Types

```ruby
# Define a custom Money type
class MoneyType < CassandraCpp::Type
  def self.type_name
    :money
  end
  
  def self.cassandra_type
    :decimal
  end
  
  def self.serialize(value)
    case value
    when Money
      value.cents.to_d / (10 ** value.currency.exponent)
    when Numeric
      BigDecimal(value.to_s)
    when String
      BigDecimal(value.gsub(/[$,]/, ''))
    when nil
      nil
    else
      raise ArgumentError, "Cannot convert #{value.class} to Money"
    end
  end
  
  def self.deserialize(value)
    return nil if value.nil?
    Money.new((value * 100).to_i, 'USD')  # Assuming USD
  end
  
  def self.validate(value)
    return true if value.nil?
    
    case value
    when Money, Numeric, String
      true
    else
      false
    end
  end
end

# Register the custom type
CassandraCpp::Types.register(MoneyType)

# Use in models
class Product < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :price, :money
  column :cost, :money
  
  def profit
    price - cost
  end
end

# Usage
product = Product.new(
  id: CassandraCpp::Uuid.generate,
  name: 'Widget',
  price: Money.new(2999, 'USD'),  # $29.99
  cost: Money.new(1500, 'USD')    # $15.00
)

puts product.profit  # => $14.99
```

### Complex Type Converters

```ruby
# Encrypted field type
class EncryptedType < CassandraCpp::Type
  def self.type_name
    :encrypted
  end
  
  def self.cassandra_type
    :blob
  end
  
  def self.serialize(value)
    return nil if value.nil?
    
    encrypted = encrypt(value.to_s)
    encrypted.force_encoding('BINARY')
  end
  
  def self.deserialize(value)
    return nil if value.nil?
    
    decrypt(value)
  end
  
  private
  
  def self.encrypt(plaintext)
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.encrypt
    
    key = derive_key
    cipher.key = key
    iv = cipher.random_iv
    cipher.auth_data = ''
    
    encrypted = cipher.update(plaintext) + cipher.final
    tag = cipher.auth_tag
    
    # Combine IV, tag, and encrypted data
    [iv, tag, encrypted].map { |part| 
      Base64.strict_encode64(part) 
    }.join('|')
  end
  
  def self.decrypt(ciphertext)
    iv_b64, tag_b64, encrypted_b64 = ciphertext.split('|')
    iv = Base64.strict_decode64(iv_b64)
    tag = Base64.strict_decode64(tag_b64)
    encrypted = Base64.strict_decode64(encrypted_b64)
    
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.decrypt
    
    key = derive_key
    cipher.key = key
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.auth_data = ''
    
    cipher.update(encrypted) + cipher.final
  end
  
  def self.derive_key
    # Use a key derivation function
    salt = ENV.fetch('ENCRYPTION_SALT', 'default_salt')
    password = ENV.fetch('ENCRYPTION_PASSWORD', 'default_password')
    
    OpenSSL::PKCS5.pbkdf2_hmac(
      password,
      salt,
      10000,  # iterations
      32      # key length
    )
  end
end

# JSON type with schema validation
class JsonType < CassandraCpp::Type
  def self.type_name
    :json
  end
  
  def self.cassandra_type
    :text
  end
  
  def self.serialize(value)
    return nil if value.nil?
    
    case value
    when String
      # Validate JSON
      JSON.parse(value)
      value
    when Hash, Array
      JSON.generate(value)
    else
      JSON.generate(value.as_json)
    end
  rescue JSON::ParserError => e
    raise CassandraCpp::SerializationError, "Invalid JSON: #{e.message}"
  end
  
  def self.deserialize(value)
    return nil if value.nil?
    
    JSON.parse(value, symbolize_names: true)
  rescue JSON::ParserError
    # Return raw value if not valid JSON
    value
  end
end

# Compressed text type
class CompressedTextType < CassandraCpp::Type
  def self.type_name
    :compressed_text
  end
  
  def self.cassandra_type
    :blob
  end
  
  def self.serialize(value)
    return nil if value.nil?
    
    # Only compress if text is large enough
    text = value.to_s
    return text if text.bytesize < 1024
    
    compressed = Zlib::Deflate.deflate(text)
    
    # Prepend a marker to indicate compression
    "ZLIB:#{Base64.strict_encode64(compressed)}"
  end
  
  def self.deserialize(value)
    return nil if value.nil?
    return value unless value.start_with?('ZLIB:')
    
    compressed_data = Base64.strict_decode64(value[5..-1])
    Zlib::Inflate.inflate(compressed_data)
  rescue => e
    # Return original value if decompression fails
    puts "Decompression failed: #{e.message}"
    value
  end
end
```

## Event Hooks and Callbacks

### Model-Level Hooks

```ruby
class User < CassandraCpp::Model
  # Lifecycle hooks
  before_save :normalize_data
  after_save :update_search_index
  before_destroy :cleanup_associations
  after_destroy :audit_deletion
  
  # Validation hooks
  before_validation :set_defaults
  after_validation :log_validation_errors
  
  # Connection hooks
  after_connect :log_connection
  before_disconnect :cleanup_resources
  
  private
  
  def normalize_data
    self.email = email.downcase.strip if email.present?
    self.name = name.strip if name.present?
  end
  
  def update_search_index
    SearchIndexer.update_async(self)
  end
  
  def cleanup_associations
    # Remove dependent records
    posts.destroy_all
    comments.destroy_all
  end
  
  def audit_deletion
    AuditLog.create!(
      action: 'user_deleted',
      user_id: id,
      metadata: attributes.to_json,
      timestamp: Time.now
    )
  end
end
```

### Global Event Hooks

```ruby
# Global event system
module CassandraCppEvents
  def self.subscribe(event_name, &block)
    subscribers[event_name] ||= []
    subscribers[event_name] << block
  end
  
  def self.publish(event_name, data = {})
    return unless subscribers[event_name]
    
    subscribers[event_name].each do |subscriber|
      begin
        subscriber.call(data)
      rescue => e
        puts "Event subscriber error: #{e.message}"
      end
    end
  end
  
  private
  
  def self.subscribers
    @subscribers ||= {}
  end
end

# Subscribe to events
CassandraCppEvents.subscribe(:model_created) do |data|
  puts "Model created: #{data[:model].class.name} - #{data[:model].id}"
  MetricsCollector.increment('model.created', tags: ["type:#{data[:model].class.name}"])
end

CassandraCppEvents.subscribe(:query_executed) do |data|
  duration = data[:duration]
  query = data[:query]
  
  if duration > 1000  # Log slow queries
    SlowQueryLogger.log(query: query, duration: duration)
  end
  
  MetricsCollector.timing('query.duration', duration)
end

CassandraCppEvents.subscribe(:connection_failed) do |data|
  AlertManager.send_alert(
    "Connection failed to #{data[:host]}: #{data[:error]}"
  )
end

# Publish events from models
class User < CassandraCpp::Model
  after_create do
    CassandraCppEvents.publish(:model_created, model: self)
  end
  
  after_save do
    CassandraCppEvents.publish(:model_updated, 
      model: self, 
      changes: previous_changes
    )
  end
end
```

### Custom Event Hooks

```ruby
class EventHookSystem
  def initialize
    @hooks = Hash.new { |h, k| h[k] = [] }
    @mutex = Mutex.new
  end
  
  def register_hook(event, priority: 0, &block)
    @mutex.synchronize do
      @hooks[event] << { callback: block, priority: priority }
      @hooks[event].sort_by! { |hook| -hook[:priority] }
    end
  end
  
  def trigger_hooks(event, context = {})
    hooks = @mutex.synchronize { @hooks[event].dup }
    
    hooks.each do |hook|
      begin
        result = hook[:callback].call(context)
        
        # Allow hooks to modify context
        context.merge!(result) if result.is_a?(Hash)
        
        # Allow hooks to cancel execution
        break if result == :cancel
      rescue => e
        puts "Hook error for #{event}: #{e.message}"
      end
    end
    
    context
  end
end

# Usage in models
class User < CassandraCpp::Model
  def self.hook_system
    @hook_system ||= EventHookSystem.new
  end
  
  # Register hooks
  hook_system.register_hook(:before_save, priority: 10) do |context|
    user = context[:user]
    user.updated_at = Time.now
    context
  end
  
  hook_system.register_hook(:after_save, priority: 5) do |context|
    user = context[:user]
    CacheInvalidator.invalidate_user_cache(user.id)
    context
  end
  
  # Trigger hooks in model methods
  def save
    context = self.class.hook_system.trigger_hooks(:before_save, user: self)
    
    return false if context == :cancel
    
    result = super
    
    if result
      self.class.hook_system.trigger_hooks(:after_save, user: self)
    end
    
    result
  end
end
```

## Connection Management

### Advanced Pool Configuration

```ruby
class AdvancedConnectionPool
  def initialize(config)
    @config = config
    @pools = {}
    @health_checker = HealthChecker.new
    @load_balancer = LoadBalancer.new(config.load_balancing_strategy)
  end
  
  def connection_for(keyspace, consistency: nil)
    pool_key = "#{keyspace}:#{consistency}"
    
    @pools[pool_key] ||= create_pool(keyspace, consistency)
    
    pool = @pools[pool_key]
    
    # Get connection with health checking
    connection = pool.checkout
    
    unless @health_checker.healthy?(connection)
      pool.checkin(connection)
      connection = create_new_connection(keyspace, consistency)
    end
    
    connection
  end
  
  def with_connection(keyspace, consistency: nil)
    connection = connection_for(keyspace, consistency)
    
    begin
      yield connection
    ensure
      return_connection(connection)
    end
  end
  
  def stats
    {
      total_pools: @pools.size,
      pool_stats: @pools.map do |key, pool|
        {
          key: key,
          size: pool.size,
          available: pool.available,
          checked_out: pool.checked_out
        }
      end
    }
  end
  
  private
  
  def create_pool(keyspace, consistency)
    ConnectionPool.new(
      size: @config.pool_size,
      timeout: @config.pool_timeout
    ) do
      create_new_connection(keyspace, consistency)
    end
  end
  
  def create_new_connection(keyspace, consistency)
    host = @load_balancer.select_host
    
    connection = CassandraCpp::Connection.new(
      host: host,
      keyspace: keyspace,
      consistency: consistency,
      **@config.connection_options
    )
    
    connection.connect
    connection
  end
end

# Health checking system
class HealthChecker
  def initialize(check_interval: 30)
    @check_interval = check_interval
    @last_checks = {}
  end
  
  def healthy?(connection)
    return false unless connection&.connected?
    
    # Rate limit health checks
    last_check = @last_checks[connection.object_id]
    return true if last_check && (Time.now - last_check) < @check_interval
    
    begin
      # Simple health check query
      connection.execute("SELECT key FROM system.local LIMIT 1")
      @last_checks[connection.object_id] = Time.now
      true
    rescue => e
      puts "Health check failed: #{e.message}"
      false
    end
  end
end
```

### Connection Failover

```ruby
class FailoverConnectionManager
  def initialize(hosts, options = {})
    @hosts = hosts.map { |host| HostInfo.new(host) }
    @options = options
    @circuit_breakers = {}
    @retry_scheduler = RetryScheduler.new
  end
  
  def execute_with_failover(query, *args, &block)
    attempts = 0
    max_attempts = @options[:max_attempts] || 3
    
    hosts_to_try = available_hosts
    
    hosts_to_try.each do |host|
      attempts += 1
      
      begin
        return execute_on_host(host, query, *args, &block)
      rescue CassandraCpp::ConnectionError => e
        handle_connection_error(host, e)
        
        # Retry on next host if available
        next if attempts < max_attempts && has_more_hosts?(hosts_to_try, host)
        
        # Re-raise if no more hosts or max attempts reached
        raise
      rescue CassandraCpp::TimeoutError => e
        handle_timeout_error(host, e)
        
        # Retry with exponential backoff
        if attempts < max_attempts
          sleep(calculate_backoff_delay(attempts))
          next
        end
        
        raise
      end
    end
    
    raise CassandraCpp::NoHostsAvailable, "All hosts failed"
  end
  
  private
  
  def available_hosts
    @hosts.select do |host|
      circuit_breaker = @circuit_breakers[host.address]
      !circuit_breaker || circuit_breaker.allow_request?
    end
  end
  
  def execute_on_host(host, query, *args, &block)
    connection = get_connection(host)
    
    if block_given?
      yield connection
    else
      connection.execute(query, *args)
    end
  end
  
  def handle_connection_error(host, error)
    circuit_breaker = get_circuit_breaker(host)
    circuit_breaker.record_failure
    
    # Schedule retry
    @retry_scheduler.schedule_retry(host, delay: 30)
    
    puts "Connection failed to #{host.address}: #{error.message}"
  end
  
  def handle_timeout_error(host, error)
    # Don't immediately circuit break on timeout
    puts "Timeout error on #{host.address}: #{error.message}"
  end
  
  def get_circuit_breaker(host)
    @circuit_breakers[host.address] ||= CircuitBreaker.new(
      failure_threshold: 5,
      recovery_timeout: 60,
      half_open_max_calls: 3
    )
  end
  
  def calculate_backoff_delay(attempt)
    base_delay = 0.1
    max_delay = 5.0
    
    delay = base_delay * (2 ** (attempt - 1))
    [delay, max_delay].min
  end
end

class HostInfo
  attr_reader :address, :datacenter, :rack
  
  def initialize(host)
    if host.is_a?(String)
      @address = host
      @datacenter = 'unknown'
      @rack = 'unknown'
    else
      @address = host[:address]
      @datacenter = host[:datacenter] || 'unknown'
      @rack = host[:rack] || 'unknown'
    end
    
    @last_failure = nil
    @failure_count = 0
  end
  
  def mark_failure
    @last_failure = Time.now
    @failure_count += 1
  end
  
  def mark_success
    @failure_count = 0
    @last_failure = nil
  end
  
  def available?
    return true unless @last_failure
    
    # Host becomes available after exponential backoff
    backoff_duration = [2 ** @failure_count, 300].min  # Max 5 minutes
    Time.now - @last_failure > backoff_duration
  end
end
```

## Security Features

### Authentication and Authorization

```ruby
class SecureUser < CassandraCpp::Model
  # Encrypted sensitive fields
  column :id, :uuid, primary_key: true
  column :email, :text
  column :encrypted_ssn, :encrypted
  column :encrypted_credit_card, :encrypted
  column :password_hash, :text
  column :roles, :set, of: :text
  
  # Audit fields
  column :created_by, :uuid
  column :updated_by, :uuid
  column :accessed_at, :timestamp
  
  # Row-level security
  def self.for_user(current_user)
    if current_user.admin?
      all  # Admins see everything
    else
      where(id: current_user.id)  # Users see only their own data
    end
  end
  
  # Field-level security
  def as_json(options = {})
    json = super(options)
    
    current_user = options[:current_user]
    
    unless current_user&.can_view_sensitive_data?
      json.delete('encrypted_ssn')
      json.delete('encrypted_credit_card')
    end
    
    json
  end
  
  # Audit access
  after_find do
    touch(:accessed_at)
    audit_access
  end
  
  private
  
  def audit_access
    SecurityAuditLog.create!(
      user_id: id,
      accessed_by: Current.user&.id,
      access_type: 'read',
      timestamp: Time.now,
      ip_address: Current.ip_address
    )
  end
end
```

### Data Masking and Redaction

```ruby
class DataMasker
  MASKING_RULES = {
    ssn: ->(value) { "***-**-#{value[-4..-1]}" },
    credit_card: ->(value) { "**** **** **** #{value[-4..-1]}" },
    email: ->(value) { 
      local, domain = value.split('@')
      "#{local[0]}***@#{domain}"
    },
    phone: ->(value) { "***-***-#{value[-4..-1]}" }
  }.freeze
  
  def self.mask_field(field_name, value, rule = nil)
    return value if value.nil? || value.empty?
    
    masking_rule = rule || MASKING_RULES[field_name.to_sym]
    
    if masking_rule
      masking_rule.call(value)
    else
      # Default masking
      "#{value[0]}#{'*' * (value.length - 2)}#{value[-1]}"
    end
  end
  
  def self.mask_record(record, fields_to_mask)
    masked_record = record.dup
    
    fields_to_mask.each do |field|
      if masked_record[field]
        masked_record[field] = mask_field(field, masked_record[field])
      end
    end
    
    masked_record
  end
end

# Usage in models
class User < CassandraCpp::Model
  SENSITIVE_FIELDS = %w[ssn credit_card phone].freeze
  
  def to_masked_json(current_user = nil)
    json = as_json
    
    # Apply masking based on permissions
    unless current_user&.can_view_sensitive_data?
      SENSITIVE_FIELDS.each do |field|
        if json[field]
          json[field] = DataMasker.mask_field(field, json[field])
        end
      end
    end
    
    json
  end
end
```

### Query Security

```ruby
class SecureQueryBuilder
  ALLOWED_OPERATORS = %w[= != > < >= <= IN CONTAINS].freeze
  ALLOWED_FUNCTIONS = %w[COUNT MAX MIN AVG SUM].freeze
  
  def self.sanitize_query(query, params = [])
    # Remove potentially dangerous SQL
    sanitized = query.gsub(/;\s*(DROP|DELETE|INSERT|UPDATE|CREATE|ALTER)/i, '')
    
    # Validate operators
    unless uses_only_allowed_operators?(sanitized)
      raise SecurityError, "Query contains disallowed operators"
    end
    
    # Validate parameters
    sanitized_params = params.map { |param| sanitize_parameter(param) }
    
    [sanitized, sanitized_params]
  end
  
  def self.validate_column_access(columns, user)
    restricted_columns = get_restricted_columns(user)
    
    unauthorized = columns & restricted_columns
    
    if unauthorized.any?
      raise SecurityError, "Access denied to columns: #{unauthorized.join(', ')}"
    end
  end
  
  private
  
  def self.uses_only_allowed_operators?(query)
    # Extract operators from query
    operators = query.scan(/\b(=|!=|>|<|>=|<=|IN|CONTAINS|LIKE)\b/i).flatten
    
    operators.all? { |op| ALLOWED_OPERATORS.include?(op.upcase) }
  end
  
  def self.sanitize_parameter(param)
    case param
    when String
      # Escape single quotes
      param.gsub("'", "''")
    when Numeric, TrueClass, FalseClass, NilClass
      param
    else
      raise SecurityError, "Invalid parameter type: #{param.class}"
    end
  end
  
  def self.get_restricted_columns(user)
    case user.role
    when 'admin'
      []
    when 'manager'
      %w[salary ssn]
    else
      %w[salary ssn credit_card]
    end
  end
end

# Usage
class User < CassandraCpp::Model
  def self.secure_where(conditions, current_user)
    # Validate column access
    column_names = extract_column_names(conditions)
    SecureQueryBuilder.validate_column_access(column_names, current_user)
    
    # Apply row-level security
    query = for_user(current_user)
    query.where(conditions)
  end
  
  def self.secure_execute(query, params, current_user)
    # Sanitize query
    sanitized_query, sanitized_params = SecureQueryBuilder.sanitize_query(query, params)
    
    # Log the query for audit
    SecurityAuditLog.create!(
      user_id: current_user.id,
      action: 'query_executed',
      query: sanitized_query,
      params: sanitized_params.to_json,
      timestamp: Time.now
    )
    
    execute(sanitized_query, *sanitized_params)
  end
end
```

## Integration Patterns

### Rails Integration

```ruby
# config/initializers/cassandra_cpp.rb
Rails.application.config.to_prepare do
  CassandraCpp.configure do |config|
    config.logger = Rails.logger
    config.hosts = Rails.application.config_for(:cassandra)['hosts']
    config.keyspace = Rails.application.config_for(:cassandra)['keyspace']
    
    # Environment-specific settings
    if Rails.env.production?
      config.compression = :lz4
      config.connections_per_local_host = 4
    elsif Rails.env.development?
      config.connections_per_local_host = 1
      config.enable_query_logging = true
    end
  end
  
  # Setup global connection
  Rails.application.config.cassandra = CassandraCpp::Cluster.build
end

# app/models/application_record.rb
class ApplicationRecord < CassandraCpp::Model
  self.abstract_class = true
  
  # Common Rails integrations
  include GlobalID::Identification if defined?(GlobalID)
  
  # Timestamp management
  before_create :set_created_at
  before_save :set_updated_at
  
  # Rails-style attribute assignment
  def attributes=(attrs)
    attrs.each { |key, value| send("#{key}=", value) }
  end
  
  # ActiveRecord-compatible methods
  def persisted?
    !new_record?
  end
  
  def to_param
    id.to_s
  end
  
  private
  
  def set_created_at
    self.created_at ||= Time.now if respond_to?(:created_at=)
  end
  
  def set_updated_at
    self.updated_at = Time.now if respond_to?(:updated_at=)
  end
end

# ActionController integration
class ApplicationController < ActionController::Base
  private
  
  def cassandra_session
    @cassandra_session ||= Rails.application.config.cassandra.connect
  end
end
```

### Sidekiq Integration

```ruby
class CassandraJob < ApplicationJob
  queue_as :cassandra_operations
  
  # Retry with exponential backoff for transient failures
  retry_on CassandraCpp::Errors::TimeoutError, wait: :exponentially_longer
  retry_on CassandraCpp::Errors::UnavailableError, wait: :exponentially_longer
  
  # Don't retry on permanent failures
  discard_on CassandraCpp::Errors::SyntaxError
  discard_on CassandraCpp::Errors::UnauthorizedError
  
  def perform(*args)
    # Ensure fresh connection for background job
    CassandraCpp::Cluster.current.with_fresh_connection do
      perform_cassandra_work(*args)
    end
  end
  
  private
  
  def perform_cassandra_work(*args)
    # Override in subclasses
    raise NotImplementedError
  end
end

# Example background jobs
class UserDataMigrationJob < CassandraJob
  def perform_cassandra_work(user_ids)
    User.where(id: user_ids).find_each do |user|
      migrate_user_data(user)
    end
  end
  
  private
  
  def migrate_user_data(user)
    # Migration logic
  end
end

class BatchInsertJob < CassandraJob
  def perform_cassandra_work(records_data)
    User.batch do
      records_data.each { |data| User.create!(data) }
    end
  end
end

# Job scheduling
class DataProcessor
  def self.schedule_user_migration(user_ids, batch_size: 100)
    user_ids.each_slice(batch_size) do |batch|
      UserDataMigrationJob.perform_later(batch)
    end
  end
  
  def self.schedule_batch_insert(records, batch_size: 50)
    records.each_slice(batch_size) do |batch|
      BatchInsertJob.perform_later(batch)
    end
  end
end
```

### GraphQL Integration

```ruby
# GraphQL type definitions
class UserType < GraphQL::Schema::Object
  field :id, ID, null: false
  field :email, String, null: true
  field :name, String, null: true
  field :created_at, GraphQL::Types::ISO8601DateTime, null: true
  
  # Efficient field resolution
  field :posts, [PostType], null: true do
    argument :limit, Integer, required: false, default_value: 10
  end
  
  def posts(limit:)
    # Use dataloader to avoid N+1 queries
    dataloader
      .with(PostsByUserLoader, object.id)
      .load
      .then { |posts| posts.first(limit) }
  end
end

# DataLoader for efficient batching
class PostsByUserLoader < GraphQL::Batch::Loader
  def perform(user_ids)
    # Batch load posts for all requested users
    posts_by_user = Post
      .where(user_id: user_ids)
      .group_by(&:user_id)
    
    user_ids.each do |user_id|
      fulfill(user_id, posts_by_user[user_id] || [])
    end
  end
end

# Resolver with connection support
class Users::IndexResolver < GraphQL::Schema::Resolver
  type UserType.connection_type, null: false
  
  argument :filter, String, required: false
  argument :sort_by, String, required: false, default_value: 'created_at'
  argument :sort_direction, String, required: false, default_value: 'desc'
  
  def resolve(filter: nil, sort_by:, sort_direction:, **args)
    users = User.all
    
    # Apply filtering
    if filter.present?
      users = users.where("name CONTAINS ? ALLOW FILTERING", filter)
    end
    
    # Apply sorting
    users = users.order(sort_by => sort_direction.to_sym)
    
    # Return connection-compatible object
    users
  end
end

# Mutation with error handling
class Users::CreateMutation < GraphQL::Schema::Mutation
  argument :input, Users::CreateInput, required: true
  
  field :user, UserType, null: true
  field :errors, [String], null: false
  
  def resolve(input:)
    user = User.new(input.to_h)
    
    if user.save
      {
        user: user,
        errors: []
      }
    else
      {
        user: nil,
        errors: user.errors.full_messages
      }
    end
  rescue CassandraCpp::Errors::QueryError => e
    {
      user: nil,
      errors: ["Database error: #{e.message}"]
    }
  end
end
```

## Next Steps

Now that you've learned about the advanced features of Cassandra-CPP, you can:

- [Troubleshooting](09_troubleshooting.md) - Debug complex issues
- [Contributing](10_contributing.md) - Help improve the gem

These advanced features enable you to build sophisticated, high-performance applications that take full advantage of both Cassandra's capabilities and Ruby's flexibility.