# Troubleshooting Guide

This comprehensive troubleshooting guide helps you diagnose and resolve common issues with Cassandra-CPP, from installation problems to performance bottlenecks and production issues.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Connection Problems](#connection-problems)
- [Query Errors](#query-errors)
- [Performance Issues](#performance-issues)
- [Memory Problems](#memory-problems)
- [Production Debugging](#production-debugging)
- [Error Reference](#error-reference)
- [Diagnostic Tools](#diagnostic-tools)
- [Common Patterns](#common-patterns)
- [Getting Help](#getting-help)

## Installation Issues

### Native Extension Compilation Failures

**Problem**: Gem installation fails during native extension compilation

```bash
ERROR: Failed to build gem native extension.
Could not find cassandra.h
```

**Solutions**:

1. **Missing DataStax C++ driver**:
```bash
# Ubuntu/Debian
sudo apt-get install cassandra-cpp-driver-dev

# CentOS/RHEL
sudo yum install cassandra-cpp-driver-devel

# macOS
brew install cassandra-cpp-driver
```

2. **Missing development tools**:
```bash
# Ubuntu/Debian
sudo apt-get install build-essential cmake

# macOS
xcode-select --install

# CentOS/RHEL
sudo yum groupinstall "Development Tools"
```

3. **Set environment variables**:
```bash
export CPATH="/usr/local/include:$CPATH"
export LIBRARY_PATH="/usr/local/lib:$LIBRARY_PATH"
export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

gem install cassandra-cpp
```

### Version Compatibility Issues

**Problem**: Incompatible versions between Ruby, driver, and Cassandra

```ruby
# Check versions
puts "Ruby version: #{RUBY_VERSION}"
puts "Cassandra-CPP version: #{CassandraCpp::VERSION}"
puts "Driver version: #{CassandraCpp.driver_version}"

# Verify compatibility
compatibility = CassandraCpp.check_compatibility
puts "Compatible: #{compatibility[:compatible]}"
puts "Issues: #{compatibility[:issues]}" unless compatibility[:compatible]
```

**Solutions**:
- Refer to the [compatibility matrix](01_installation.md#compatibility-matrix)
- Upgrade Ruby: `rbenv install 3.0.0 && rbenv global 3.0.0`
- Update driver: Follow installation guide for your platform

### Docker and Container Issues

**Problem**: Installation fails in Docker containers

```dockerfile
# Fix common Docker issues
FROM ruby:3.0

# Install system dependencies first
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libuv1-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Build and install DataStax driver
RUN cd /tmp && \
    wget https://github.com/datastax/cpp-driver/archive/2.16.2.tar.gz && \
    tar xzf 2.16.2.tar.gz && \
    cd cpp-driver-2.16.2 && \
    mkdir build && cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Now install the gem
RUN gem install cassandra-cpp
```

## Connection Problems

### No Hosts Available

**Problem**: Cannot connect to any Cassandra nodes

```ruby
CassandraCpp::Errors::NoHostsAvailable: No hosts available
```

**Diagnostic Steps**:

```ruby
# Test individual host connectivity
def test_host_connectivity(host, port = 9042)
  begin
    socket = TCPSocket.new(host, port)
    socket.close
    puts "✓ #{host}:#{port} is reachable"
    true
  rescue => e
    puts "✗ #{host}:#{port} failed: #{e.message}"
    false
  end
end

# Test all configured hosts
hosts = ['10.0.0.1', '10.0.0.2', '10.0.0.3']
hosts.each { |host| test_host_connectivity(host) }

# Check DNS resolution
hosts.each do |host|
  begin
    ip = Resolv.getaddress(host)
    puts "#{host} resolves to #{ip}"
  rescue => e
    puts "DNS resolution failed for #{host}: #{e.message}"
  end
end
```

**Solutions**:

1. **Network connectivity**:
```bash
# Test ping
ping -c 3 cassandra-node-1

# Test port connectivity
telnet cassandra-node-1 9042
nc -zv cassandra-node-1 9042
```

2. **Firewall issues**:
```bash
# Check if port 9042 is open
sudo netstat -tlnp | grep 9042
sudo ss -tlnp | grep 9042

# Test from application server
nmap -p 9042 cassandra-node-1
```

3. **Configuration issues**:
```ruby
# Check Cassandra configuration
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['cassandra-node-1', 'cassandra-node-2']
  config.port = 9042
  config.connect_timeout = 10000  # 10 seconds
  config.request_timeout = 5000   # 5 seconds
  
  # Enable debug logging
  config.log_level = :debug
end
```

### Authentication Failures

**Problem**: Authentication errors when connecting

```ruby
CassandraCpp::Errors::AuthenticationError: Authentication failed
```

**Diagnostic Steps**:

```ruby
def test_authentication(username, password)
  begin
    cluster = CassandraCpp::Cluster.build do |config|
      config.hosts = ['localhost']
      config.username = username
      config.password = password
    end
    
    session = cluster.connect
    puts "✓ Authentication successful"
    session.close
    true
  rescue CassandraCpp::Errors::AuthenticationError => e
    puts "✗ Authentication failed: #{e.message}"
    false
  rescue => e
    puts "✗ Other error: #{e.message}"
    false
  end
end

# Test credentials
test_authentication('cassandra', 'cassandra')
test_authentication(ENV['CASS_USER'], ENV['CASS_PASS'])
```

**Solutions**:

1. **Verify credentials**:
```bash
# Test with cqlsh
cqlsh -u cassandra -p cassandra cassandra-node-1

# Check environment variables
echo $CASSANDRA_USERNAME
echo $CASSANDRA_PASSWORD
```

2. **Check Cassandra configuration**:
```yaml
# cassandra.yaml
authenticator: PasswordAuthenticator
authorizer: CassandraAuthorizer
```

### SSL/TLS Issues

**Problem**: SSL connection failures

```ruby
CassandraCpp::Errors::SSLError: SSL handshake failed
```

**Diagnostic Steps**:

```ruby
def test_ssl_connection(host, port = 9042)
  begin
    context = OpenSSL::SSL::SSLContext.new
    context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    
    socket = TCPSocket.new(host, port)
    ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, context)
    ssl_socket.connect
    
    puts "✓ SSL connection successful"
    puts "Cipher: #{ssl_socket.cipher[0]}"
    puts "Protocol: #{ssl_socket.cipher[1]}"
    
    ssl_socket.close
    socket.close
    true
  rescue => e
    puts "✗ SSL connection failed: #{e.message}"
    false
  end
end

test_ssl_connection('secure-cassandra-node')
```

**Solutions**:

1. **Certificate issues**:
```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.ssl = true
  config.ssl_options = {
    ca_file: '/path/to/ca.pem',
    verify_mode: :peer,
    verify_hostname: false  # Try this first
  }
end
```

2. **Test certificate chain**:
```bash
# Verify certificate
openssl s_client -connect cassandra-node:9042 -servername cassandra-node

# Check certificate expiration
openssl x509 -in /path/to/cert.pem -text -noout | grep "Not After"
```

## Query Errors

### Syntax Errors

**Problem**: CQL syntax errors

```ruby
CassandraCpp::Errors::SyntaxError: Invalid syntax at line 1:15
```

**Diagnostic Steps**:

```ruby
def validate_cql(query)
  # Basic syntax validation
  if query.strip.empty?
    puts "✗ Empty query"
    return false
  end
  
  # Check for common issues
  issues = []
  issues << "Missing semicolon" unless query.strip.end_with?(';')
  issues << "Contains SQL syntax" if query =~ /\bJOIN\b|\bLEFT\b|\bRIGHT\b/i
  issues << "Uses LIMIT without ORDER BY" if query =~ /\bLIMIT\b/i && query !~ /\bORDER BY\b/i
  
  if issues.any?
    puts "✗ Potential issues: #{issues.join(', ')}"
    return false
  end
  
  puts "✓ Query looks valid"
  true
end

# Test queries
validate_cql("SELECT * FROM users WHERE id = ?")
validate_cql("SELECT * FROM users JOIN posts ON users.id = posts.user_id")  # Invalid
```

**Solutions**:

1. **Use CQL-specific syntax**:
```ruby
# Bad: SQL syntax
"SELECT * FROM users u JOIN posts p ON u.id = p.user_id"

# Good: CQL with denormalized data
"SELECT * FROM user_posts WHERE user_id = ?"
```

2. **Common CQL corrections**:
```ruby
# Pagination
# Bad: OFFSET (not supported)
"SELECT * FROM users LIMIT 10 OFFSET 20"

# Good: Token-based pagination
"SELECT * FROM users WHERE token(id) > token(?) LIMIT 10"

# Ordering
# Bad: ORDER BY non-clustering column
"SELECT * FROM users ORDER BY email"

# Good: ORDER BY clustering column
"SELECT * FROM users WHERE user_id = ? ORDER BY created_at DESC"
```

### ALLOW FILTERING Warnings

**Problem**: Queries require ALLOW FILTERING

```ruby
CassandraCpp::Errors::InvalidError: Cannot execute this query as it might involve data filtering
```

**Diagnostic Steps**:

```ruby
def analyze_filtering_query(model, conditions)
  table_info = model.table_info
  
  puts "Table: #{table_info[:name]}"
  puts "Partition keys: #{table_info[:partition_keys]}"
  puts "Clustering keys: #{table_info[:clustering_keys]}"
  puts "Indexes: #{table_info[:indexes]}"
  
  conditions.each do |column, value|
    if table_info[:partition_keys].include?(column)
      puts "✓ #{column} is a partition key"
    elsif table_info[:clustering_keys].include?(column)
      puts "✓ #{column} is a clustering key"
    elsif table_info[:indexes].include?(column)
      puts "✓ #{column} has an index"
    else
      puts "✗ #{column} requires filtering (no index)"
    end
  end
end

analyze_filtering_query(User, { email: 'john@example.com', status: 'active' })
```

**Solutions**:

1. **Add secondary indexes**:
```ruby
class User < CassandraCpp::Model
  column :email, :text, index: true
  column :status, :text, index: true
end

# Or manually
session.execute("CREATE INDEX users_email_idx ON users (email)")
```

2. **Redesign table structure**:
```ruby
# Instead of filtering on non-key columns
# CREATE TABLE users_by_status (
#   status text,
#   user_id uuid,
#   email text,
#   name text,
#   PRIMARY KEY (status, user_id)
# )

class UserByStatus < CassandraCpp::Model
  table_name 'users_by_status'
  
  column :status, :text, partition_key: true
  column :user_id, :uuid, clustering_key: true
  column :email, :text
  column :name, :text
end

# Efficient query without filtering
UserByStatus.where(status: 'active').limit(100)
```

### Timeout Errors

**Problem**: Query timeouts

```ruby
CassandraCpp::Errors::TimeoutError: Request timed out after 5000ms
```

**Diagnostic Steps**:

```ruby
def analyze_slow_query(query, *params)
  start_time = Time.now
  
  begin
    # Execute with tracing
    result = session.execute(query, *params, trace: true)
    duration = Time.now - start_time
    
    puts "Query completed in #{duration * 1000}ms"
    
    # Analyze trace
    trace = result.execution_info.trace
    trace.events.each do |event|
      puts "#{event.source}: #{event.activity} (#{event.elapsed}μs)"
    end
    
  rescue CassandraCpp::Errors::TimeoutError => e
    duration = Time.now - start_time
    puts "Query timed out after #{duration * 1000}ms"
    
    # Suggest optimizations
    suggest_timeout_optimizations(query)
  end
end

def suggest_timeout_optimizations(query)
  puts "\nOptimization suggestions:"
  
  if query.include?('ALLOW FILTERING')
    puts "- Remove ALLOW FILTERING by adding indexes or redesigning table"
  end
  
  if query.include?('SELECT *')
    puts "- Select only needed columns"
  end
  
  unless query.include?('LIMIT')
    puts "- Add LIMIT clause to prevent large result sets"
  end
  
  if query =~ /WHERE.*=.*AND/
    puts "- Consider using composite partition keys"
  end
end
```

**Solutions**:

1. **Increase timeout**:
```ruby
# Per-query timeout
session.execute(query, timeout: 30000)  # 30 seconds

# Global timeout
cluster = CassandraCpp::Cluster.build do |config|
  config.request_timeout = 15000  # 15 seconds
end
```

2. **Optimize query**:
```ruby
# Add pagination
"SELECT * FROM large_table LIMIT 1000"

# Select specific columns
"SELECT id, name, email FROM users WHERE status = ?"

# Use token-based queries for large scans
"SELECT * FROM users WHERE token(id) > token(?) LIMIT 1000"
```

## Performance Issues

### Slow Queries

**Problem**: Queries are slower than expected

**Diagnostic Steps**:

```ruby
class QueryProfiler
  def self.profile_query(description, &block)
    # Memory before
    memory_before = `ps -o rss= -p #{Process.pid}`.to_i
    
    # CPU time before
    cpu_before = Process.times
    
    # Wall clock time
    start_time = Time.now
    
    result = yield
    
    # Calculate metrics
    duration = Time.now - start_time
    cpu_after = Process.times
    memory_after = `ps -o rss= -p #{Process.pid}`.to_i
    
    cpu_time = (cpu_after.utime - cpu_before.utime) + 
               (cpu_after.stime - cpu_before.stime)
    
    puts "Query Profile: #{description}"
    puts "  Duration: #{(duration * 1000).round(2)}ms"
    puts "  CPU time: #{(cpu_time * 1000).round(2)}ms"
    puts "  Memory delta: #{memory_after - memory_before}KB"
    puts "  CPU efficiency: #{((cpu_time / duration) * 100).round(1)}%"
    
    result
  end
end

# Profile problematic queries
QueryProfiler.profile_query("User search") do
  User.where(status: 'active').limit(100).to_a
end
```

**Solutions**:

1. **Use prepared statements**:
```ruby
# Slow: Re-parsing every time
User.where(email: email).first

# Fast: Prepared statement
class User < CassandraCpp::Model
  prepare :find_by_email, "SELECT * FROM users WHERE email = ?"
  
  def self.find_by_email(email)
    execute_prepared(:find_by_email, email).first
  end
end
```

2. **Optimize data model**:
```ruby
# Slow: Multiple queries
user = User.find(id)
posts = Post.where(user_id: id).limit(10)

# Fast: Denormalized data
class UserWithRecentPosts < CassandraCpp::Model
  column :user_id, :uuid, primary_key: true
  column :name, :text
  column :email, :text
  column :recent_posts, :list, of: :text  # JSON serialized posts
end
```

### High Memory Usage

**Problem**: Application consuming too much memory

**Diagnostic Steps**:

```ruby
def memory_analysis
  # Ruby object counts
  ObjectSpace.count_objects.each do |type, count|
    puts "#{type}: #{count}" if count > 1000
  end
  
  # Memory usage by gem
  require 'objspace'
  
  cassandra_objects = ObjectSpace.each_object.select do |obj|
    obj.class.name.start_with?('CassandraCpp')
  end
  
  puts "CassandraCpp objects: #{cassandra_objects.size}"
  
  # Connection pool stats
  if CassandraCpp::Cluster.current
    pool_stats = CassandraCpp::Cluster.current.connection_pool_stats
    puts "Active connections: #{pool_stats[:active]}"
    puts "Pool size: #{pool_stats[:size]}"
  end
end

# Monitor memory growth
def monitor_memory_growth
  initial_memory = `ps -o rss= -p #{Process.pid}`.to_i
  
  1000.times do |i|
    User.create!(name: "User #{i}", email: "user#{i}@example.com")
    
    if i % 100 == 0
      current_memory = `ps -o rss= -p #{Process.pid}`.to_i
      growth = current_memory - initial_memory
      puts "After #{i} operations: #{growth}KB growth"
      
      # Force GC to see if memory is freed
      GC.start
      after_gc = `ps -o rss= -p #{Process.pid}`.to_i
      puts "After GC: #{after_gc - initial_memory}KB"
    end
  end
end
```

**Solutions**:

1. **Optimize connection pool**:
```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Reduce connection pool size
  config.connections_per_local_host = 2
  config.max_connections_per_local_host = 4
  
  # Enable connection reaping
  config.idle_timeout = 120  # Close idle connections
  config.heartbeat_interval = 30
end
```

2. **Process data in batches**:
```ruby
# Memory-efficient processing
def process_users_efficiently
  User.find_each(batch_size: 100) do |user|
    process_user(user)
    
    # Explicitly nil references
    user = nil
    
    # Periodic garbage collection
    GC.start if rand(100) == 0
  end
end
```

### Connection Pool Exhaustion

**Problem**: Running out of available connections

```ruby
CassandraCpp::Errors::PoolTimeoutError: Timeout waiting for connection from pool
```

**Diagnostic Steps**:

```ruby
def diagnose_connection_pool
  cluster = CassandraCpp::Cluster.current
  stats = cluster.connection_pool_stats
  
  puts "Connection Pool Diagnostics:"
  puts "  Total connections: #{stats[:total]}"
  puts "  Active connections: #{stats[:active]}"
  puts "  Idle connections: #{stats[:idle]}"
  puts "  Pool utilization: #{(stats[:active].to_f / stats[:total] * 100).round(1)}%"
  
  if stats[:active] == stats[:total]
    puts "⚠️  Pool is exhausted!"
    
    # Check for connection leaks
    check_connection_leaks
  end
end

def check_connection_leaks
  # Monitor open file descriptors
  fd_count = `lsof -p #{Process.pid} | wc -l`.to_i
  puts "Open file descriptors: #{fd_count}"
  
  # Check for TCP connections to Cassandra
  cassandra_connections = `netstat -an | grep :9042 | grep ESTABLISHED | wc -l`.to_i
  puts "TCP connections to Cassandra: #{cassandra_connections}"
end
```

**Solutions**:

1. **Increase pool size**:
```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.connections_per_local_host = 8
  config.max_connections_per_local_host = 16
end
```

2. **Fix connection leaks**:
```ruby
# Bad: Not returning connections
def bad_pattern
  10.times do
    session = cluster.connect
    session.execute("SELECT * FROM users LIMIT 1")
    # session never closed!
  end
end

# Good: Proper connection management
def good_pattern
  cluster.with_session do |session|
    10.times do
      session.execute("SELECT * FROM users LIMIT 1")
    end
  end
end
```

## Memory Problems

### Memory Leaks

**Problem**: Memory usage continuously increases

**Diagnostic Steps**:

```ruby
require 'memory_profiler'

def profile_memory_usage(&block)
  report = MemoryProfiler.report do
    yield
  end
  
  puts "Memory Report:"
  puts "Total allocated: #{report.total_allocated} objects / #{report.total_allocated_memsize} bytes"
  puts "Total retained: #{report.total_retained} objects / #{report.total_retained_memsize} bytes"
  
  # Show top allocating locations
  puts "\nTop allocating locations:"
  report.allocated_memory_by_location.first(10).each do |location, stats|
    puts "  #{location}: #{stats[:count]} objects / #{stats[:memsize]} bytes"
  end
  
  # Show top retained locations
  puts "\nTop retained locations:"
  report.retained_memory_by_location.first(10).each do |location, stats|
    puts "  #{location}: #{stats[:count]} objects / #{stats[:memsize]} bytes"
  end
end

# Profile suspected code
profile_memory_usage do
  1000.times { User.create!(name: 'Test', email: 'test@example.com') }
end
```

**Solutions**:

1. **Explicit cleanup**:
```ruby
class User < CassandraCpp::Model
  after_destroy :cleanup_references
  
  private
  
  def cleanup_references
    # Clear any circular references
    @associations = nil
    @cached_attributes = nil
  end
end
```

2. **Use weak references for caches**:
```ruby
require 'weakref'

class WeakCache
  def initialize
    @cache = {}
  end
  
  def get(key)
    ref = @cache[key]
    return nil unless ref
    
    begin
      ref.__getobj__
    rescue WeakRef::RefError
      @cache.delete(key)
      nil
    end
  end
  
  def set(key, value)
    @cache[key] = WeakRef.new(value)
  end
end
```

### Large Result Sets

**Problem**: Queries returning too much data cause memory issues

**Solutions**:

1. **Streaming with find_each**:
```ruby
# Memory-efficient processing
User.find_each(batch_size: 1000) do |user|
  process_user(user)
end

# Instead of loading everything
users = User.all.to_a  # Loads all users into memory!
```

2. **Manual pagination**:
```ruby
def process_all_users_paginated
  last_token = nil
  processed = 0
  
  loop do
    query = User.limit(1000)
    query = query.where("token(id) > ?", last_token) if last_token
    
    batch = query.to_a
    break if batch.empty?
    
    batch.each do |user|
      process_user(user)
      processed += 1
    end
    
    last_token = batch.last.token(:id)
    
    # Clear batch from memory
    batch.clear
    batch = nil
    
    # Periodic GC
    GC.start if processed % 10000 == 0
    
    puts "Processed #{processed} users"
  end
end
```

## Production Debugging

### Connection Monitoring

```ruby
class ConnectionMonitor
  def self.start_monitoring
    Thread.new do
      loop do
        begin
          monitor_connections
          sleep 60  # Check every minute
        rescue => e
          puts "Monitor error: #{e.message}"
        end
      end
    end
  end
  
  def self.monitor_connections
    cluster = CassandraCpp::Cluster.current
    return unless cluster
    
    # Connection stats
    stats = cluster.connection_pool_stats
    
    # Log metrics
    puts "#{Time.now}: Connections: #{stats[:active]}/#{stats[:total]}, " \
         "Requests: #{stats[:requests_per_second]}, " \
         "Latency: #{stats[:avg_latency]}ms"
    
    # Check for issues
    if stats[:active] > stats[:total] * 0.8
      alert("High connection usage: #{stats[:active]}/#{stats[:total]}")
    end
    
    if stats[:avg_latency] > 100
      alert("High latency: #{stats[:avg_latency]}ms")
    end
    
    # Host-specific stats
    cluster.hosts.each do |host|
      host_stats = cluster.host_stats(host)
      
      unless host_stats[:available]
        alert("Host unavailable: #{host}")
      end
    end
  end
  
  def self.alert(message)
    puts "ALERT: #{message}"
    # Send to monitoring system
  end
end

# Start monitoring
ConnectionMonitor.start_monitoring
```

### Query Logging

```ruby
class QueryLogger
  def self.enable(options = {})
    @log_slow_queries = options[:slow_queries] != false
    @slow_query_threshold = options[:slow_threshold] || 1000  # ms
    @log_all_queries = options[:all_queries] == true
    
    # Hook into query execution
    CassandraCpp.configure do |config|
      config.before_execute = method(:log_query_start)
      config.after_execute = method(:log_query_end)
    end
  end
  
  def self.log_query_start(query, params)
    Thread.current[:query_start_time] = Time.now
    Thread.current[:query_info] = { query: query, params: params }
    
    if @log_all_queries
      puts "QUERY START: #{sanitize_query(query)} with #{params.inspect}"
    end
  end
  
  def self.log_query_end(result, error = nil)
    return unless Thread.current[:query_start_time]
    
    duration = (Time.now - Thread.current[:query_start_time]) * 1000
    query_info = Thread.current[:query_info]
    
    if error
      puts "QUERY ERROR (#{duration.round(2)}ms): #{error.message}"
      puts "  Query: #{sanitize_query(query_info[:query])}"
    elsif @log_slow_queries && duration > @slow_query_threshold
      puts "SLOW QUERY (#{duration.round(2)}ms): #{sanitize_query(query_info[:query])}"
      puts "  Params: #{query_info[:params].inspect}"
    end
    
    # Clean up thread locals
    Thread.current[:query_start_time] = nil
    Thread.current[:query_info] = nil
  end
  
  private
  
  def self.sanitize_query(query)
    # Remove sensitive data from logs
    query.gsub(/\b[\w.-]+@[\w.-]+\.\w+\b/, '[EMAIL]')
         .gsub(/\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b/, '[CARD]')
         .gsub(/\b\d{3}-\d{2}-\d{4}\b/, '[SSN]')
  end
end

# Enable query logging
QueryLogger.enable(
  slow_queries: true,
  slow_threshold: 500,  # 500ms
  all_queries: Rails.env.development?
)
```

### Health Checks

```ruby
class HealthCheck
  def self.perform
    results = {
      timestamp: Time.now,
      overall_status: 'healthy',
      checks: {}
    }
    
    # Database connectivity
    results[:checks][:database] = check_database_connectivity
    
    # Connection pool
    results[:checks][:connection_pool] = check_connection_pool
    
    # Query performance
    results[:checks][:query_performance] = check_query_performance
    
    # Memory usage
    results[:checks][:memory_usage] = check_memory_usage
    
    # Determine overall status
    failed_checks = results[:checks].select { |_, check| check[:status] != 'ok' }
    
    if failed_checks.any?
      results[:overall_status] = 'unhealthy'
      results[:failed_checks] = failed_checks.keys
    end
    
    results
  end
  
  private
  
  def self.check_database_connectivity
    begin
      start_time = Time.now
      result = CassandraCpp::Cluster.current.execute("SELECT key FROM system.local")
      duration = Time.now - start_time
      
      {
        status: 'ok',
        response_time: duration,
        details: "Connected successfully"
      }
    rescue => e
      {
        status: 'error',
        error: e.message,
        details: "Failed to connect to database"
      }
    end
  end
  
  def self.check_connection_pool
    begin
      stats = CassandraCpp::Cluster.current.connection_pool_stats
      utilization = stats[:active].to_f / stats[:total]
      
      status = case utilization
               when 0..0.7 then 'ok'
               when 0.7..0.9 then 'warning'
               else 'critical'
               end
      
      {
        status: status,
        utilization: utilization,
        active_connections: stats[:active],
        total_connections: stats[:total]
      }
    rescue => e
      {
        status: 'error',
        error: e.message
      }
    end
  end
  
  def self.check_query_performance
    begin
      start_time = Time.now
      User.limit(1).to_a
      duration = (Time.now - start_time) * 1000
      
      status = case duration
               when 0..100 then 'ok'
               when 100..500 then 'warning'
               else 'critical'
               end
      
      {
        status: status,
        response_time: duration,
        threshold: 'Simple query should complete under 100ms'
      }
    rescue => e
      {
        status: 'error',
        error: e.message
      }
    end
  end
  
  def self.check_memory_usage
    memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    
    status = case memory_mb
             when 0..512 then 'ok'
             when 512..1024 then 'warning'
             else 'critical'
             end
    
    {
      status: status,
      memory_usage_mb: memory_mb,
      threshold: 'Should stay under 512MB'
    }
  end
end

# Expose health check endpoint (Rails example)
class HealthController < ApplicationController
  def show
    health_result = HealthCheck.perform
    
    status_code = case health_result[:overall_status]
                  when 'healthy' then 200
                  when 'unhealthy' then 503
                  else 500
                  end
    
    render json: health_result, status: status_code
  end
end
```

## Error Reference

### Common Error Types

```ruby
# Connection Errors
CassandraCpp::Errors::NoHostsAvailable
  # Cause: Cannot connect to any Cassandra nodes
  # Solutions: Check network, firewall, host configuration

CassandraCpp::Errors::AuthenticationError
  # Cause: Invalid credentials
  # Solutions: Verify username/password, check authentication configuration

CassandraCpp::Errors::SSLError
  # Cause: SSL/TLS configuration issues
  # Solutions: Check certificates, SSL settings

# Query Errors
CassandraCpp::Errors::SyntaxError
  # Cause: Invalid CQL syntax
  # Solutions: Fix CQL syntax, use CQL-specific features

CassandraCpp::Errors::InvalidError
  # Cause: Query requires ALLOW FILTERING or violates constraints
  # Solutions: Add indexes, redesign table, use ALLOW FILTERING cautiously

CassandraCpp::Errors::TimeoutError
  # Cause: Query took too long to execute
  # Solutions: Optimize query, increase timeout, add indexes

CassandraCpp::Errors::UnavailableError
  # Cause: Not enough replicas available for consistency level
  # Solutions: Check cluster health, use lower consistency level

# Pool Errors
CassandraCpp::Errors::PoolTimeoutError
  # Cause: No connections available in pool
  # Solutions: Increase pool size, fix connection leaks

CassandraCpp::Errors::PoolExhausted
  # Cause: All connections are in use
  # Solutions: Increase pool size, improve query performance
```

## Diagnostic Tools

### Connection Diagnostic Tool

```ruby
class ConnectionDiagnostic
  def self.run(hosts)
    report = {
      timestamp: Time.now,
      hosts: {}
    }
    
    hosts.each do |host|
      report[:hosts][host] = diagnose_host(host)
    end
    
    print_report(report)
    report
  end
  
  private
  
  def self.diagnose_host(host)
    result = {
      host: host,
      reachable: false,
      port_open: false,
      ssl_working: false,
      auth_working: false,
      query_working: false,
      latency: nil,
      errors: []
    }
    
    # Test basic connectivity
    begin
      socket = TCPSocket.new(host, 9042)
      socket.close
      result[:reachable] = true
      result[:port_open] = true
    rescue => e
      result[:errors] << "Connection failed: #{e.message}"
      return result
    end
    
    # Test Cassandra protocol
    begin
      start_time = Time.now
      
      cluster = CassandraCpp::Cluster.build do |config|
        config.hosts = [host]
        config.connect_timeout = 5000
      end
      
      session = cluster.connect
      session.execute("SELECT key FROM system.local")
      
      result[:query_working] = true
      result[:latency] = Time.now - start_time
      
      session.close
      cluster.close
      
    rescue CassandraCpp::Errors::AuthenticationError => e
      result[:errors] << "Authentication failed: #{e.message}"
    rescue CassandraCpp::Errors::SSLError => e
      result[:errors] << "SSL error: #{e.message}"
    rescue => e
      result[:errors] << "Query failed: #{e.message}"
    end
    
    result
  end
  
  def self.print_report(report)
    puts "Connection Diagnostic Report - #{report[:timestamp]}"
    puts "=" * 60
    
    report[:hosts].each do |host, result|
      puts "Host: #{host}"
      puts "  Reachable: #{result[:reachable] ? '✓' : '✗'}"
      puts "  Port Open: #{result[:port_open] ? '✓' : '✗'}"
      puts "  Query Working: #{result[:query_working] ? '✓' : '✗'}"
      puts "  Latency: #{result[:latency] ? "#{(result[:latency] * 1000).round(2)}ms" : 'N/A'}"
      
      if result[:errors].any?
        puts "  Errors:"
        result[:errors].each { |error| puts "    - #{error}" }
      end
      
      puts
    end
  end
end

# Usage
ConnectionDiagnostic.run(['node1.cassandra.com', 'node2.cassandra.com'])
```

### Query Performance Analyzer

```ruby
class QueryAnalyzer
  def self.analyze(query, params = [])
    puts "Analyzing Query:"
    puts "  Query: #{query}"
    puts "  Params: #{params.inspect}"
    puts
    
    # Parse query components
    components = parse_query(query)
    analyze_components(components)
    
    # Execute with timing
    execute_with_analysis(query, params)
    
    # Provide recommendations
    provide_recommendations(query, components)
  end
  
  private
  
  def self.parse_query(query)
    {
      has_where: query.include?('WHERE'),
      has_limit: query.include?('LIMIT'),
      has_order_by: query.include?('ORDER BY'),
      has_allow_filtering: query.include?('ALLOW FILTERING'),
      select_all: query.include?('SELECT *'),
      table_name: extract_table_name(query)
    }
  end
  
  def self.analyze_components(components)
    puts "Query Analysis:"
    
    if components[:select_all]
      puts "  ⚠️  Selecting all columns (SELECT *)"
    end
    
    unless components[:has_where]
      puts "  ⚠️  No WHERE clause (full table scan)"
    end
    
    if components[:has_allow_filtering]
      puts "  ⚠️  Uses ALLOW FILTERING"
    end
    
    unless components[:has_limit]
      puts "  ⚠️  No LIMIT clause"
    end
    
    puts
  end
  
  def self.execute_with_analysis(query, params)
    puts "Execution Analysis:"
    
    # Execute with trace
    start_time = Time.now
    result = CassandraCpp::Cluster.current.execute(query, *params, trace: true)
    duration = Time.now - start_time
    
    puts "  Duration: #{(duration * 1000).round(2)}ms"
    puts "  Rows returned: #{result.size}"
    
    # Analyze trace
    if result.execution_info.trace
      trace = result.execution_info.trace
      puts "  Coordinator: #{trace.coordinator}"
      puts "  Started at: #{trace.started_at}"
      puts "  Duration: #{trace.duration}μs"
      
      # Show slowest operations
      slow_operations = trace.events.sort_by(&:elapsed).reverse.first(3)
      puts "  Slowest operations:"
      slow_operations.each do |event|
        puts "    #{event.activity}: #{event.elapsed}μs"
      end
    end
    
    puts
  end
  
  def self.provide_recommendations(query, components)
    puts "Recommendations:"
    
    if components[:select_all]
      puts "  - Select only needed columns for better performance"
    end
    
    if components[:has_allow_filtering]
      puts "  - Add secondary indexes to avoid ALLOW FILTERING"
      puts "  - Consider redesigning table structure"
    end
    
    unless components[:has_limit]
      puts "  - Add LIMIT clause to prevent large result sets"
    end
    
    if components[:has_where] && !components[:has_allow_filtering]
      puts "  ✓ Query looks well-optimized"
    end
  end
  
  def self.extract_table_name(query)
    match = query.match(/FROM\s+(\w+)/i)
    match ? match[1] : 'unknown'
  end
end

# Usage
QueryAnalyzer.analyze(
  "SELECT * FROM users WHERE status = ? ALLOW FILTERING",
  ['active']
)
```

## Common Patterns

### Retry Pattern

```ruby
class RetryableOperation
  MAX_RETRIES = 3
  RETRY_DELAY = 0.1
  
  def self.execute(max_retries: MAX_RETRIES, delay: RETRY_DELAY, &block)
    retries = 0
    
    begin
      yield
    rescue CassandraCpp::Errors::TimeoutError,
           CassandraCpp::Errors::UnavailableError => e
      
      retries += 1
      
      if retries <= max_retries
        sleep(delay * retries)  # Exponential backoff
        retry
      else
        raise
      end
    rescue CassandraCpp::Errors::SyntaxError,
           CassandraCpp::Errors::AuthenticationError => e
      # Don't retry these errors
      raise
    end
  end
end

# Usage
RetryableOperation.execute do
  User.where(status: 'active').limit(100).to_a
end
```

### Circuit Breaker Pattern

```ruby
class CircuitBreaker
  def initialize(failure_threshold: 5, recovery_timeout: 60)
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @failure_count = 0
    @last_failure_time = nil
    @state = :closed  # :closed, :open, :half_open
  end
  
  def call(&block)
    case @state
    when :open
      if Time.now - @last_failure_time > @recovery_timeout
        @state = :half_open
        attempt_call(&block)
      else
        raise CassandraCpp::CircuitBreakerOpenError
      end
    when :half_open
      attempt_call(&block)
    when :closed
      attempt_call(&block)
    end
  end
  
  private
  
  def attempt_call(&block)
    begin
      result = yield
      on_success
      result
    rescue => e
      on_failure
      raise
    end
  end
  
  def on_success
    @failure_count = 0
    @state = :closed
  end
  
  def on_failure
    @failure_count += 1
    @last_failure_time = Time.now
    
    if @failure_count >= @failure_threshold
      @state = :open
    end
  end
end

# Usage
circuit_breaker = CircuitBreaker.new(failure_threshold: 3, recovery_timeout: 30)

begin
  result = circuit_breaker.call do
    User.where(status: 'active').limit(100).to_a
  end
rescue CassandraCpp::CircuitBreakerOpenError
  puts "Circuit breaker is open, using cached data"
  result = get_cached_users
end
```

## Getting Help

### Information to Provide

When seeking help with Cassandra-CPP issues, provide:

1. **Environment details**:
```ruby
puts "Ruby version: #{RUBY_VERSION}"
puts "Cassandra-CPP version: #{CassandraCpp::VERSION}"
puts "Platform: #{RUBY_PLATFORM}"
puts "OS: #{`uname -a`.strip}"
```

2. **Cassandra cluster info**:
```ruby
session.execute("SELECT * FROM system.local").each do |row|
  puts "Cassandra version: #{row['release_version']}"
  puts "Cluster name: #{row['cluster_name']}"
  puts "Data center: #{row['data_center']}"
end
```

3. **Configuration**:
```ruby
# Sanitize sensitive information
config = CassandraCpp.configuration.to_h
config.delete(:password)
config.delete(:ssl_options)
puts "Configuration: #{config.inspect}"
```

4. **Error details**:
```ruby
begin
  # Problem code
rescue => e
  puts "Error class: #{e.class}"
  puts "Error message: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
end
```

### Support Resources

- **GitHub Issues**: [github.com/your-org/cassandra-cpp/issues](https://github.com/your-org/cassandra-cpp/issues)
- **Documentation**: [cassandra-cpp.readthedocs.io](https://cassandra-cpp.readthedocs.io)
- **Stack Overflow**: Tag questions with `cassandra-cpp`
- **Community Slack**: [#cassandra-cpp](https://ruby-cassandra.slack.com)

### Before Opening an Issue

1. **Search existing issues**: Your problem might already be reported
2. **Check compatibility**: Ensure versions are compatible
3. **Minimal reproduction**: Create a minimal example that reproduces the issue
4. **Test with latest version**: Update to the latest gem version
5. **Check Cassandra logs**: Look for errors in Cassandra server logs

## Next Steps

- [Contributing](10_contributing.md) - Help improve Cassandra-CPP
- [Performance Guide](07_performance.md) - Optimize your usage
- [Configuration Guide](02_configuration.md) - Fine-tune your setup

With this troubleshooting guide, you should be able to diagnose and resolve most issues you encounter with Cassandra-CPP. Remember that many performance and reliability issues can be prevented with proper configuration and following best practices outlined in the other documentation sections.