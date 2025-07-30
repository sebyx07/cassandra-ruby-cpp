# Performance Guide

This guide covers performance optimization techniques for Cassandra-CPP, from basic best practices to advanced tuning strategies. Learn how to maximize throughput, minimize latency, and efficiently use system resources.

## Table of Contents

- [Performance Overview](#performance-overview)
- [Benchmarking](#benchmarking) 
- [Connection Optimization](#connection-optimization)
- [Query Optimization](#query-optimization)
- [Memory Management](#memory-management)
- [Batch Operations](#batch-operations)
- [Caching Strategies](#caching-strategies)
- [Monitoring and Profiling](#monitoring-and-profiling)
- [Advanced Optimizations](#advanced-optimizations)
- [Production Tuning](#production-tuning)

## Performance Overview

### Why Cassandra-CPP is Fast

Cassandra-CPP delivers exceptional performance through:

1. **Native C++ Driver**: Direct use of DataStax C++ driver eliminates Ruby overhead
2. **Connection Pooling**: Efficient connection reuse and management
3. **Prepared Statements**: Automatic query preparation and caching  
4. **Batch Operations**: Optimized bulk operations
5. **Memory Management**: Careful handling of Ruby-C++ memory boundaries
6. **Asynchronous Operations**: Non-blocking I/O for concurrent requests

### Performance Metrics

```ruby
# Basic performance monitoring
class PerformanceMonitor
  def self.benchmark_query(description, &block)
    start_time = Time.now
    result = yield
    duration = Time.now - start_time
    
    puts "#{description}: #{duration * 1000}ms"
    result
  end
  
  def self.monitor_connection_pool
    cluster = CassandraCpp::Cluster.current
    
    puts "Active connections: #{cluster.connection_count}"
    puts "Pool utilization: #{cluster.pool_utilization}%"
    puts "Pending requests: #{cluster.pending_requests}"
  end
end

# Usage
result = PerformanceMonitor.benchmark_query("User lookup") do
  User.find(user_id)
end
```

## Benchmarking

### Built-in Benchmarking Tools

```ruby
# Enable built-in benchmarking
CassandraCpp.configure do |config|
  config.enable_benchmarking = true
end

# Benchmark specific operations
CassandraCpp.benchmark do |bench|
  bench.single_insert(1000) { User.create!(name: 'Test', email: 'test@example.com') }
  bench.batch_insert(100, 10) { User.batch_create(user_data) }
  bench.simple_query(1000) { User.where(status: 'active').limit(10) }
  bench.complex_query(100) { User.joins(:posts).where(posts: { published: true }) }
end

# Results:
# Single Insert    : 1000 ops in 1.2s (833 ops/sec, 1.2ms avg)
# Batch Insert     : 100 batches (1000 ops) in 0.8s (1250 ops/sec, 0.8ms avg)
# Simple Query     : 1000 ops in 0.9s (1111 ops/sec, 0.9ms avg)
# Complex Query    : 100 ops in 1.5s (67 ops/sec, 15ms avg)
```

### Custom Benchmarking

```ruby
require 'benchmark'

def benchmark_operations
  user_ids = (1..1000).map { CassandraCpp::Uuid.generate }
  
  Benchmark.bmbm do |bench|
    bench.report("Individual finds") do
      user_ids.each { |id| User.find(id) rescue nil }
    end
    
    bench.report("Batch find") do
      User.find(user_ids)
    end
    
    bench.report("Prepared statement") do
      stmt = User.prepare("SELECT * FROM users WHERE id = ?")
      user_ids.each { |id| User.execute(stmt.bind(id)) }
    end
    
    bench.report("Raw CQL") do
      user_ids.each do |id|
        User.execute("SELECT * FROM users WHERE id = ?", id)
      end
    end
  end
end
```

### Comparative Benchmarks

```ruby
# Compare with other Ruby Cassandra drivers
class DriverComparison
  def self.run_comparison
    operations = 1000
    data = generate_test_data(operations)
    
    # Cassandra-CPP
    cpp_time = Benchmark.realtime do
      data.each { |user| User.create!(user) }
    end
    
    # Ruby Cassandra driver (for comparison)
    ruby_time = Benchmark.realtime do
      data.each { |user| RubyUser.create!(user) }
    end
    
    puts "Cassandra-CPP: #{operations / cpp_time} ops/sec"
    puts "Ruby Driver:   #{operations / ruby_time} ops/sec"
    puts "Improvement:   #{(ruby_time / cpp_time).round(2)}x faster"
  end
end
```

## Connection Optimization

### Pool Configuration

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['10.0.0.1', '10.0.0.2', '10.0.0.3']
  
  # Connection pool sizing
  config.connections_per_local_host = 4      # Start with 4 connections
  config.max_connections_per_local_host = 16 # Scale up to 16
  config.connections_per_remote_host = 1     # Minimal remote connections
  config.max_connections_per_remote_host = 4
  
  # Request handling
  config.max_requests_per_connection = 2048  # High concurrent requests
  config.queue_size_io = 8192               # Large I/O queue
  config.queue_size_event = 8192            # Large event queue
  
  # Connection lifecycle
  config.heartbeat_interval = 30            # Keep connections alive
  config.idle_timeout = 300                 # 5 minute idle timeout
  
  # Performance tuning
  config.tcp_nodelay = true                 # Disable Nagle's algorithm
  config.tcp_keepalive = true               # Enable TCP keepalive
end
```

### Connection Monitoring

```ruby
class ConnectionMonitor
  def self.monitor_cluster(cluster)
    metrics = cluster.metrics
    
    puts "Connection Pool Status:"
    puts "  Active connections: #{metrics.total_connections}"
    puts "  Available connections: #{metrics.available_connections}"
    puts "  In-flight requests: #{metrics.in_flight_requests}"
    puts "  Queue depth: #{metrics.queue_depth}"
    
    # Per-host breakdown
    cluster.hosts.each do |host|
      host_metrics = cluster.host_metrics(host)
      puts "  #{host}:"
      puts "    Connections: #{host_metrics.connections}"
      puts "    Requests/sec: #{host_metrics.requests_per_second}"
      puts "    Avg latency: #{host_metrics.avg_latency}ms"
    end
  end
  
  def self.detect_connection_issues(cluster)
    metrics = cluster.metrics
    
    # Warn about pool exhaustion
    if metrics.pool_utilization > 0.8
      puts "WARNING: Connection pool utilization high (#{metrics.pool_utilization}%)"
    end
    
    # Detect slow hosts
    cluster.hosts.each do |host|
      host_metrics = cluster.host_metrics(host)
      if host_metrics.avg_latency > 100
        puts "WARNING: High latency to #{host}: #{host_metrics.avg_latency}ms"
      end
    end
  end
end
```

## Query Optimization

### Prepared Statements

```ruby
# Automatic preparation for repeated queries
class User < CassandraCpp::Model
  # Cache prepared statements at class level
  class << self
    def find_by_email_prepared
      @find_by_email_stmt ||= prepare("SELECT * FROM users WHERE email = ? ALLOW FILTERING")
    end
    
    def update_last_login_prepared
      @update_last_login_stmt ||= prepare("UPDATE users SET last_login = ? WHERE id = ?")
    end
  end
  
  def self.find_by_email(email)
    result = execute(find_by_email_prepared.bind(email))
    result.first
  end
  
  def update_last_login!
    self.class.execute(
      self.class.update_last_login_prepared.bind(Time.now, id)
    )
  end
end

# Performance comparison
Benchmark.bmbm do |bench|
  emails = (1..1000).map { |i| "user#{i}@example.com" }
  
  bench.report("Raw CQL") do
    emails.each do |email|
      User.execute("SELECT * FROM users WHERE email = ? ALLOW FILTERING", email)
    end
  end
  
  bench.report("Prepared statements") do
    stmt = User.prepare("SELECT * FROM users WHERE email = ? ALLOW FILTERING")
    emails.each do |email|
      User.execute(stmt.bind(email))
    end
  end
end
```

### Query Planning

```ruby
# Analyze query performance
class QueryPlanner
  def self.analyze_query(model, conditions)
    query = model.where(conditions)
    
    # Get query plan
    plan = query.explain
    
    puts "Query Analysis for: #{query.to_cql}"
    puts "  Estimated rows: #{plan.estimated_rows}"
    puts "  Uses index: #{plan.uses_index?}"
    puts "  Requires filtering: #{plan.requires_filtering?}"
    puts "  Partition keys: #{plan.partition_key_restrictions}"
    puts "  Clustering keys: #{plan.clustering_key_restrictions}"
    
    # Performance recommendations
    suggest_optimizations(plan)
  end
  
  def self.suggest_optimizations(plan)
    puts "\nOptimization Suggestions:"
    
    if plan.requires_filtering?
      puts "  - Consider creating a secondary index"
      puts "  - Or redesign table to avoid ALLOW FILTERING"
    end
    
    if plan.estimated_rows > 10000
      puts "  - Consider adding LIMIT clause"
      puts "  - Use pagination for large result sets"
    end
    
    unless plan.uses_index?
      puts "  - Query uses full table scan"
      puts "  - Consider adding appropriate indexes"
    end
  end
end

# Usage
QueryPlanner.analyze_query(User, { status: 'active', country: 'US' })
```

### Index Optimization

```ruby
class User < CassandraCpp::Model
  # Strategic index placement
  column :email, :text, index: true          # High cardinality
  column :status, :text, index: true         # Low cardinality but frequently queried
  column :country, :text, index: true        # Medium cardinality
  column :created_at, :timestamp
  
  # Composite indexes for common query patterns
  index [:country, :status], name: 'country_status_idx'
  index [:status, :created_at], name: 'status_created_idx'
  
  # Collection indexes
  column :tags, :set, of: :text
  index :tags, name: 'user_tags_idx'
  
  # Optimize common queries
  def self.active_in_country(country)
    # Uses country_status_idx efficiently
    where(country: country, status: 'active')
  end
  
  def self.recent_active_users(limit = 100)
    # Uses status_created_idx efficiently
    where(status: 'active')
      .order(created_at: :desc)
      .limit(limit)
  end
end

# Monitor index usage
class IndexMonitor
  def self.analyze_index_usage(table_name)
    # Query system tables for index statistics
    result = execute(<<-CQL)
      SELECT index_name, reads, avg_sstable_hit_ratio
      FROM system.table_estimates
      WHERE keyspace_name = ? AND table_name = ?
    CQL, keyspace, table_name)
    
    result.each do |row|
      puts "Index: #{row['index_name']}"
      puts "  Reads: #{row['reads']}"
      puts "  Hit ratio: #{row['avg_sstable_hit_ratio']}"
    end
  end
end
```

## Memory Management

### Object Allocation Optimization

```ruby
# Minimize object allocations
class OptimizedUser < CassandraCpp::Model
  # Use symbols for keys to reduce string allocations
  COLUMN_MAPPING = {
    id: 'id',
    email: 'email', 
    name: 'name'
  }.freeze
  
  # Reuse result arrays
  def self.find_batch(ids)
    # Pre-allocate result array
    results = Array.new(ids.size)
    placeholders = (['?'] * ids.size).join(', ')
    
    query_result = execute("SELECT * FROM users WHERE id IN (#{placeholders})", *ids)
    
    # Build results hash for O(1) lookup
    results_hash = {}
    query_result.each { |row| results_hash[row['id']] = row }
    
    # Return in same order as input
    ids.map { |id| results_hash[id] }.compact
  end
  
  # Pool frequently used objects
  @uuid_pool = []
  
  def self.get_uuid
    @uuid_pool.pop || CassandraCpp::Uuid.generate
  end
  
  def self.return_uuid(uuid)
    @uuid_pool.push(uuid) if @uuid_pool.size < 100
  end
end
```

### Memory Pool Management

```ruby
class MemoryPool
  def initialize(size: 1000)
    @pool = []
    @max_size = size
  end
  
  def get_buffer(size)
    buffer = @pool.find { |b| b.size >= size }
    if buffer
      @pool.delete(buffer)
      buffer.clear
    else
      String.new(capacity: size)
    end
  end
  
  def return_buffer(buffer)
    return if @pool.size >= @max_size
    @pool << buffer
  end
end

# Global buffer pool for query results
BUFFER_POOL = MemoryPool.new(size: 500)

class User < CassandraCpp::Model
  def self.find_with_pooled_buffer(id)
    buffer = BUFFER_POOL.get_buffer(1024)
    
    begin
      # Use buffer for query processing
      result = execute_with_buffer("SELECT * FROM users WHERE id = ?", buffer, id)
      result.first
    ensure
      BUFFER_POOL.return_buffer(buffer)
    end
  end
end
```

### Garbage Collection Optimization

```ruby
# Configure GC for high-throughput scenarios
GC::Profiler.enable

# Monitor GC impact
class GCMonitor
  def self.monitor_gc(&block)
    GC::Profiler.clear
    GC.start  # Clean slate
    
    start_time = Time.now
    yield
    duration = Time.now - start_time
    
    gc_time = GC::Profiler.total_time
    gc_percentage = (gc_time / duration) * 100
    
    puts "Total time: #{duration}s"
    puts "GC time: #{gc_time}s (#{gc_percentage.round(2)}%)"
    puts "GC count: #{GC.count}"
    
    GC::Profiler.report if gc_percentage > 10
  end
end

# Usage
GCMonitor.monitor_gc do
  1000.times { User.create!(name: 'Test', email: 'test@example.com') }
end
```

## Batch Operations

### Efficient Batching

```ruby
class OptimizedBatch
  def self.batch_insert(records, batch_size: 100)
    records.each_slice(batch_size) do |batch|
      # Group by partition key for efficiency
      partitioned_batches = batch.group_by { |record| record[:user_id] }
      
      partitioned_batches.each do |partition_key, partition_records|
        User.batch do
          partition_records.each do |record|
            User.create!(record)
          end
        end
      end
    end
  end
  
  # Async batch processing
  def self.async_batch_insert(records, batch_size: 100, concurrency: 4)
    work_queue = Queue.new
    
    # Split into batches
    records.each_slice(batch_size) { |batch| work_queue << batch }
    
    # Process with worker threads
    workers = Array.new(concurrency) do
      Thread.new do
        while (batch = work_queue.pop(true) rescue nil)
          process_batch(batch)
        end
      end
    end
    
    workers.each(&:join)
  end
  
  private
  
  def self.process_batch(batch)
    User.batch do
      batch.each { |record| User.create!(record) }
    end
  rescue => e
    # Handle batch failures gracefully
    puts "Batch failed: #{e.message}"
    # Could retry individual records
  end
end

# Performance comparison
Benchmark.bmbm do |bench|
  records = 10000.times.map do |i|
    {
      id: CassandraCpp::Uuid.generate,
      email: "user#{i}@example.com",
      name: "User #{i}"
    }
  end
  
  bench.report("Individual inserts") do
    records.each { |record| User.create!(record) }
  end
  
  bench.report("Batched inserts") do
    OptimizedBatch.batch_insert(records, batch_size: 100)
  end
  
  bench.report("Async batched inserts") do
    OptimizedBatch.async_batch_insert(records, batch_size: 100, concurrency: 4)
  end
end
```

### Smart Batching Strategies

```ruby
class SmartBatcher
  def initialize(batch_size: 100, flush_interval: 1.0)
    @batch_size = batch_size
    @flush_interval = flush_interval
    @pending_batches = Hash.new { |h, k| h[k] = [] }
    @last_flush = Time.now
    @mutex = Mutex.new
  end
  
  def add(table, record)
    @mutex.synchronize do
      partition_key = extract_partition_key(record)
      @pending_batches["#{table}:#{partition_key}"] << record
      
      flush_if_needed
    end
  end
  
  def flush
    @mutex.synchronize do
      @pending_batches.each do |key, records|
        next if records.empty?
        
        table, partition_key = key.split(':', 2)
        flush_batch(table, records)
        records.clear
      end
      
      @last_flush = Time.now
    end
  end
  
  private
  
  def flush_if_needed
    should_flush = @pending_batches.any? { |_, records| records.size >= @batch_size } ||
                   (Time.now - @last_flush) >= @flush_interval
    
    flush if should_flush
  end
  
  def flush_batch(table, records)
    model_class = table.classify.constantize
    
    model_class.batch do
      records.each { |record| model_class.create!(record) }
    end
  end
end

# Usage with automatic flushing
batcher = SmartBatcher.new(batch_size: 50, flush_interval: 0.5)

1000.times do |i|
  batcher.add('users', {
    id: CassandraCpp::Uuid.generate,
    email: "user#{i}@example.com",
    name: "User #{i}"
  })
end

batcher.flush  # Ensure all batches are processed
```

## Caching Strategies

### Query Result Caching

```ruby
class CachedModel < CassandraCpp::Model
  include CassandraCpp::Caching
  
  # Cache individual record lookups
  cache_queries :find, expires_in: 5.minutes
  
  # Cache query results with custom keys
  def self.active_users_cached
    Rails.cache.fetch("active_users:#{Date.today}", expires_in: 1.hour) do
      where(status: 'active').limit(100).to_a
    end
  end
  
  # Cache with automatic invalidation
  after_save :invalidate_cache
  after_destroy :invalidate_cache
  
  private
  
  def invalidate_cache
    Rails.cache.delete_matched("user:#{id}*")
    Rails.cache.delete_matched("active_users*")
  end
end
```

### Connection-Level Caching

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['localhost']
  
  # Enable prepared statement caching
  config.prepared_statement_cache_size = 10000
  
  # Enable metadata caching
  config.schema_metadata_cache_ttl = 300  # 5 minutes
  
  # Enable token metadata caching
  config.token_metadata_cache_ttl = 600   # 10 minutes
end
```

### Application-Level Caching

```ruby
class HighPerformanceUser < CassandraCpp::Model
  # Multi-level caching strategy
  def self.find_with_cache(id)
    # L1: In-memory cache
    if (user = @memory_cache&.[](id))
      return user
    end
    
    # L2: Redis cache
    cache_key = "user:#{id}"
    if (cached_data = Redis.current.get(cache_key))
      user = User.new(JSON.parse(cached_data))
      store_in_memory_cache(id, user)
      return user
    end
    
    # L3: Database
    user = find(id)
    if user
      # Cache in Redis
      Redis.current.setex(cache_key, 300, user.to_json)
      # Cache in memory
      store_in_memory_cache(id, user)
    end
    
    user
  end
  
  private
  
  def self.store_in_memory_cache(id, user)
    @memory_cache ||= {}
    @memory_cache[id] = user
    
    # Limit memory cache size
    if @memory_cache.size > 1000
      @memory_cache.shift  # Remove oldest entry
    end
  end
end
```

## Monitoring and Profiling

### Built-in Metrics

```ruby
# Enable comprehensive metrics
CassandraCpp.configure do |config|
  config.enable_metrics = true
  config.metrics_interval = 60  # seconds
end

# Access metrics
metrics = CassandraCpp.metrics

puts "Connection Metrics:"
puts "  Total connections: #{metrics.connections.total}"
puts "  Active connections: #{metrics.connections.active}"
puts "  Connection errors: #{metrics.connections.errors}"

puts "Query Metrics:"
puts "  Total queries: #{metrics.queries.total}"
puts "  Average latency: #{metrics.queries.avg_latency}ms"
puts "  95th percentile: #{metrics.queries.p95_latency}ms"
puts "  99th percentile: #{metrics.queries.p99_latency}ms"

puts "Error Metrics:"
puts "  Timeout errors: #{metrics.errors.timeouts}"
puts "  Unavailable errors: #{metrics.errors.unavailable}"
puts "  Other errors: #{metrics.errors.other}"
```

### Custom Profiling

```ruby
class QueryProfiler
  def initialize
    @query_stats = Hash.new { |h, k| h[k] = { count: 0, total_time: 0, max_time: 0 } }
  end
  
  def profile_query(query_type, &block)
    start_time = Time.now
    result = yield
    duration = Time.now - start_time
    
    stats = @query_stats[query_type]
    stats[:count] += 1
    stats[:total_time] += duration
    stats[:max_time] = [stats[:max_time], duration].max
    
    result
  end
  
  def report
    puts "Query Performance Report:"
    puts "=" * 50
    
    @query_stats.each do |query_type, stats|
      avg_time = stats[:total_time] / stats[:count]
      
      puts "#{query_type}:"
      puts "  Count: #{stats[:count]}"
      puts "  Total time: #{stats[:total_time].round(3)}s"
      puts "  Average time: #{avg_time.round(3)}s"
      puts "  Max time: #{stats[:max_time].round(3)}s"
      puts "  Queries/sec: #{(stats[:count] / stats[:total_time]).round(2)}"
      puts
    end
  end
end

# Usage
profiler = QueryProfiler.new

# Profile different query types
profiler.profile_query("user_lookup") do
  User.find(user_id)
end

profiler.profile_query("user_search") do
  User.where(status: 'active').limit(10).to_a
end

profiler.report
```

### APM Integration

```ruby
# New Relic integration
class User < CassandraCpp::Model
  include NewRelic::Agent::Instrumentation
  
  add_method_tracer :find, 'Custom/Cassandra/User/find'
  add_method_tracer :create!, 'Custom/Cassandra/User/create'
end

# Custom APM metrics
class CassandraMetrics
  def self.track_query(operation, &block)
    start_time = Time.now
    
    begin
      result = yield
      
      # Track success metrics
      NewRelic::Agent.record_metric("Custom/Cassandra/#{operation}/Success", 1)
      NewRelic::Agent.record_metric("Custom/Cassandra/#{operation}/Duration", 
                                   Time.now - start_time)
      
      result
    rescue => error
      # Track error metrics
      NewRelic::Agent.record_metric("Custom/Cassandra/#{operation}/Error", 1)
      NewRelic::Agent.notice_error(error)
      raise
    end
  end
end

# Usage
CassandraMetrics.track_query("user_creation") do
  User.create!(name: 'Test User', email: 'test@example.com')
end
```

## Advanced Optimizations

### Asynchronous Operations

```ruby
class AsyncUser < CassandraCpp::Model
  # Async query execution
  def self.find_async(id)
    CassandraCpp::Future.new do
      find(id)
    end
  end
  
  # Parallel query execution
  def self.find_multiple_async(ids)
    futures = ids.map do |id|
      CassandraCpp::Future.new { find(id) }
    end
    
    # Wait for all queries to complete
    CassandraCpp::Future.join(futures)
  end
  
  # Pipeline operations
  def self.pipeline_operations(operations)
    pipeline = CassandraCpp::Pipeline.new
    
    operations.each do |operation|
      case operation[:type]
      when :create
        pipeline.add { create!(operation[:data]) }
      when :update
        pipeline.add { find(operation[:id]).update!(operation[:data]) }
      when :delete
        pipeline.add { find(operation[:id]).destroy! }
      end
    end
    
    pipeline.execute
  end
end

# Usage
# Async finds
user_future = AsyncUser.find_async(user_id)
# ... do other work ...
user = user_future.value  # Block until complete

# Parallel operations
users = AsyncUser.find_multiple_async([id1, id2, id3])
```

### Token-Aware Routing

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.load_balancing_policy = :token_aware
  config.token_metadata_enabled = true
end

class User < CassandraCpp::Model
  # Optimize queries by providing partition key hint
  def self.find_with_token_hint(id)
    token = CassandraCpp::Token.for_key(id)
    
    execute_with_options(
      "SELECT * FROM users WHERE id = ?",
      { token_hint: token },
      id
    ).first
  end
  
  # Batch operations with token awareness
  def self.batch_create_optimized(users_data)
    # Group by token ranges for optimal routing
    token_groups = users_data.group_by do |data|
      CassandraCpp::Token.for_key(data[:id]).range
    end
    
    token_groups.each do |token_range, group_data|
      batch(token_hint: token_range) do
        group_data.each { |data| create!(data) }
      end
    end
  end
end
```

### Connection Multiplexing

```ruby
# Advanced connection configuration
cluster = CassandraCpp::Cluster.build do |config|
  # Enable connection multiplexing
  config.connection_multiplexing = true
  config.multiplexing_threshold = 512  # Requests per connection
  
  # Advanced pool configuration
  config.connection_pool_strategy = :adaptive
  config.pool_warmup_enabled = true
  config.pool_warmup_queries = 10
  
  # Load balancing with latency awareness
  config.load_balancing_policy = :latency_aware
  config.latency_awareness_threshold = 2.0  # 2x slower than fastest
  config.latency_awareness_exclusion_threshold = 10.0  # 10x slower
  config.latency_awareness_scale = 100  # milliseconds
end
```

## Production Tuning

### Environment-Specific Configuration

```ruby
# Production configuration
if Rails.env.production?
  CassandraCpp.configure do |config|
    # Connection settings
    config.connections_per_local_host = 8
    config.max_connections_per_local_host = 32
    config.request_timeout = 5000  # 5 seconds
    config.connect_timeout = 10000  # 10 seconds
    
    # Performance settings
    config.compression = :lz4
    config.tcp_nodelay = true
    config.tcp_keepalive = true
    
    # Reliability settings
    config.retry_policy = :exponential_backoff
    config.max_retry_attempts = 3
    config.base_retry_delay = 100  # milliseconds
    
    # Monitoring
    config.enable_metrics = true
    config.enable_tracing = false  # Too much overhead for production
    
    # Memory management
    config.prepared_statement_cache_size = 50000
    config.metadata_cache_ttl = 300
  end
end

# Staging configuration (similar to production but with more logging)
if Rails.env.staging?
  CassandraCpp.configure do |config|
    # ... production settings ...
    
    # Additional monitoring for staging
    config.enable_query_logging = true
    config.slow_query_threshold = 1000  # Log queries > 1 second
  end
end
```

### Monitoring and Alerting

```ruby
class ProductionMonitor
  def self.check_cluster_health
    cluster = CassandraCpp::Cluster.current
    metrics = cluster.metrics
    
    alerts = []
    
    # Check connection pool health
    if metrics.pool_utilization > 0.9
      alerts << "High connection pool utilization: #{metrics.pool_utilization}%"
    end
    
    # Check latency
    if metrics.avg_latency > 100
      alerts << "High average latency: #{metrics.avg_latency}ms"
    end
    
    # Check error rate
    error_rate = metrics.error_count.to_f / metrics.request_count
    if error_rate > 0.01  # 1% error rate
      alerts << "High error rate: #{(error_rate * 100).round(2)}%"
    end
    
    # Check host availability
    unavailable_hosts = cluster.hosts.select { |host| !host.available? }
    if unavailable_hosts.any?
      alerts << "Unavailable hosts: #{unavailable_hosts.map(&:address).join(', ')}"
    end
    
    # Send alerts
    alerts.each { |alert| send_alert(alert) }
    
    alerts.empty?
  end
  
  def self.send_alert(message)
    # Send to monitoring system (PagerDuty, Slack, etc.)
    puts "ALERT: #{message}"
  end
end

# Run health checks periodically
Thread.new do
  loop do
    ProductionMonitor.check_cluster_health
    sleep 60  # Check every minute
  end
end
```

### Deployment Strategies

```ruby
# Zero-downtime deployment with connection draining
class DeploymentManager
  def self.prepare_for_deployment
    cluster = CassandraCpp::Cluster.current
    
    # Stop accepting new connections
    cluster.pause_new_connections
    
    # Wait for in-flight requests to complete
    timeout = 30  # seconds
    start_time = Time.now
    
    while cluster.in_flight_requests > 0 && (Time.now - start_time) < timeout
      sleep 0.1
    end
    
    if cluster.in_flight_requests > 0
      puts "Warning: #{cluster.in_flight_requests} requests still in flight"
    end
    
    # Close connections gracefully
    cluster.close_gracefully
  end
  
  def self.post_deployment_warmup
    # Warm up connection pool
    cluster = CassandraCpp::Cluster.current
    cluster.warmup_connections
    
    # Pre-populate prepared statement cache
    User.prepare_common_statements
    Order.prepare_common_statements
    
    puts "Deployment warmup complete"
  end
end

# Usage in deployment scripts
# Before deployment:
# DeploymentManager.prepare_for_deployment

# After deployment:
# DeploymentManager.post_deployment_warmup
```

## Performance Benchmarks

### Standard Benchmarks

```ruby
# Run comprehensive benchmarks
class CassandraCppBenchmarks
  def self.run_all
    puts "Cassandra-CPP Performance Benchmarks"
    puts "=" * 50
    
    benchmark_single_operations
    benchmark_batch_operations
    benchmark_query_types
    benchmark_concurrent_operations
  end
  
  def self.benchmark_single_operations
    puts "\nSingle Operations:"
    
    Benchmark.bmbm do |bench|
      bench.report("Insert") do
        1000.times { User.create!(generate_user_data) }
      end
      
      bench.report("Find by PK") do
        1000.times { User.find(sample_user_id) }
      end
      
      bench.report("Update") do
        user = User.find(sample_user_id)
        1000.times { user.update!(name: "Updated #{rand(1000)}") }
      end
      
      bench.report("Delete") do
        1000.times do
          user = User.create!(generate_user_data)
          user.destroy!
        end
      end
    end
  end
  
  def self.benchmark_concurrent_operations
    puts "\nConcurrent Operations:"
    
    [1, 2, 4, 8, 16].each do |thread_count|
      duration = Benchmark.realtime do
        threads = Array.new(thread_count) do
          Thread.new do
            100.times { User.create!(generate_user_data) }
          end
        end
        
        threads.each(&:join)
      end
      
      ops_per_second = (thread_count * 100) / duration
      puts "#{thread_count} threads: #{ops_per_second.round} ops/sec"
    end
  end
end

# Run benchmarks
CassandraCppBenchmarks.run_all
```

### Expected Performance Numbers

Based on typical hardware (4 CPU cores, 16GB RAM, SSD storage):

```
Single Operations (1000 operations):
  Insert     : 2.5s  (400 ops/sec)
  Find by PK : 1.8s  (556 ops/sec)
  Update     : 2.2s  (455 ops/sec)
  Delete     : 2.3s  (435 ops/sec)

Batch Operations (100 batches, 10 ops each):
  Batch Insert: 0.8s  (1250 ops/sec)
  
Concurrent Operations (100 ops per thread):
  1 thread  : 400 ops/sec
  2 threads : 750 ops/sec
  4 threads : 1400 ops/sec
  8 threads : 2200 ops/sec
  16 threads: 2800 ops/sec
```

These numbers represent typical performance on a 3-node Cassandra cluster with local SSD storage and reasonable network latency (<1ms).

## Next Steps

- [Advanced Features](08_advanced_features.md) - Asynchronous operations and streaming
- [Troubleshooting](09_troubleshooting.md) - Debug performance issues
- [Contributing](10_contributing.md) - Help improve performance