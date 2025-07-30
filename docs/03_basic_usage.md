# Basic Usage Guide

This guide covers the fundamental operations with Cassandra-CPP, from establishing connections to performing CRUD operations. By the end, you'll be comfortable with the core functionality of the gem.

## Table of Contents

- [Establishing Connections](#establishing-connections)
- [Creating a Keyspace](#creating-a-keyspace)
- [Basic CRUD Operations](#basic-crud-operations)
- [Working with Data Types](#working-with-data-types)
- [Result Handling](#result-handling)
- [Error Management](#error-management)
- [Connection Lifecycle](#connection-lifecycle)
- [Batch Operations](#batch-operations)
- [Consistency Levels](#consistency-levels)
- [Common Patterns](#common-patterns)

## Establishing Connections

### Simple Connection

```ruby
require 'cassandra_cpp'

# Connect to a single node
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['127.0.0.1']
end

# Create a session
session = cluster.connect('my_keyspace')

# Execute a simple query
result = session.execute('SELECT * FROM users LIMIT 1')
```

### Connection with Options

```ruby
# More comprehensive connection setup
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['10.0.0.1', '10.0.0.2', '10.0.0.3']
  config.username = 'cassandra'
  config.password = 'cassandra'
  config.compression = :lz4
  config.request_timeout = 12000
end

# Connect without specifying keyspace
session = cluster.connect

# Use a specific keyspace
session.execute('USE my_keyspace')
```

### Connection Pool Management

```ruby
# The cluster manages connection pooling automatically
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['localhost']
  config.connections_per_local_host = 2
  config.max_connections_per_local_host = 8
end

# Sessions are lightweight - create as needed
session1 = cluster.connect('keyspace1')
session2 = cluster.connect('keyspace2')

# Sessions share the underlying connection pool
```

## Creating a Keyspace

```ruby
session = cluster.connect

# Create a keyspace with replication
session.execute(<<-CQL)
  CREATE KEYSPACE IF NOT EXISTS my_app
  WITH replication = {
    'class': 'SimpleStrategy',
    'replication_factor': 3
  }
CQL

# For production, use NetworkTopologyStrategy
session.execute(<<-CQL)
  CREATE KEYSPACE IF NOT EXISTS production_app
  WITH replication = {
    'class': 'NetworkTopologyStrategy',
    'datacenter1': 3,
    'datacenter2': 2
  }
  AND durable_writes = true
CQL

# Switch to the keyspace
session.execute('USE my_app')
```

## Basic CRUD Operations

### Create (INSERT)

```ruby
# Create a table
session.execute(<<-CQL)
  CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email TEXT,
    name TEXT,
    age INT,
    created_at TIMESTAMP
  )
CQL

# Simple insert
session.execute(
  "INSERT INTO users (id, email, name, age, created_at) 
   VALUES (?, ?, ?, ?, ?)",
  CassandraCpp::Uuid.generate,
  'john@example.com',
  'John Doe',
  30,
  Time.now
)

# Insert with TTL
session.execute(
  "INSERT INTO users (id, email, name) 
   VALUES (?, ?, ?) 
   USING TTL 3600",  # Expires in 1 hour
  CassandraCpp::Uuid.generate,
  'temp@example.com',
  'Temporary User'
)

# Insert with consistency level
statement = session.prepare(
  "INSERT INTO users (id, email, name, age) VALUES (?, ?, ?, ?)"
)
session.execute(
  statement.bind(
    CassandraCpp::Uuid.generate,
    'jane@example.com',
    'Jane Doe',
    25
  ),
  consistency: :quorum
)
```

### Read (SELECT)

```ruby
# Select all
result = session.execute('SELECT * FROM users')
result.each do |row|
  puts "#{row['name']} - #{row['email']}"
end

# Select with conditions
result = session.execute(
  'SELECT * FROM users WHERE id = ?',
  'f47ac10b-58cc-4372-a567-0e02b2c3d479'
)

# Select specific columns
result = session.execute(
  'SELECT name, email FROM users WHERE age > ? ALLOW FILTERING',
  25
)

# Using prepared statements (recommended)
select_stmt = session.prepare('SELECT * FROM users WHERE email = ?')
result = session.execute(select_stmt.bind('john@example.com'))

# With limit and ordering (requires appropriate keys)
result = session.execute(
  'SELECT * FROM users LIMIT 10'
)
```

### Update

```ruby
# Simple update
session.execute(
  'UPDATE users SET age = ? WHERE id = ?',
  31,
  user_id
)

# Update multiple columns
session.execute(
  'UPDATE users SET name = ?, age = ?, updated_at = ? WHERE id = ?',
  'John Smith',
  31,
  Time.now,
  user_id
)

# Conditional update (lightweight transaction)
result = session.execute(
  'UPDATE users SET email = ? WHERE id = ? IF email = ?',
  'newemail@example.com',
  user_id,
  'oldemail@example.com'
)

if result.first['[applied]']
  puts 'Update successful'
else
  puts 'Condition not met'
end

# Update with TTL
session.execute(
  'UPDATE users USING TTL 86400 SET status = ? WHERE id = ?',
  'active',
  user_id
)
```

### Delete

```ruby
# Delete a row
session.execute(
  'DELETE FROM users WHERE id = ?',
  user_id
)

# Delete specific columns
session.execute(
  'DELETE email, phone FROM users WHERE id = ?',
  user_id
)

# Conditional delete
result = session.execute(
  'DELETE FROM users WHERE id = ? IF age > ?',
  user_id,
  18
)

# Delete with timestamp (for conflict resolution)
session.execute(
  'DELETE FROM users USING TIMESTAMP ? WHERE id = ?',
  (Time.now.to_f * 1_000_000).to_i,  # microseconds
  user_id
)
```

## Working with Data Types

### Basic Types

```ruby
# Create table with various types
session.execute(<<-CQL)
  CREATE TABLE IF NOT EXISTS data_types_example (
    id UUID PRIMARY KEY,
    text_col TEXT,
    int_col INT,
    bigint_col BIGINT,
    float_col FLOAT,
    double_col DOUBLE,
    boolean_col BOOLEAN,
    timestamp_col TIMESTAMP,
    date_col DATE,
    time_col TIME,
    blob_col BLOB,
    inet_col INET,
    decimal_col DECIMAL,
    varint_col VARINT
  )
CQL

# Insert with type conversion
session.execute(
  "INSERT INTO data_types_example 
   (id, text_col, int_col, bigint_col, float_col, boolean_col, 
    timestamp_col, blob_col, inet_col, decimal_col)
   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  CassandraCpp::Uuid.generate,
  'Hello World',
  42,
  9223372036854775807,  # max bigint
  3.14159,
  true,
  Time.now,
  "\x00\x01\x02\x03".force_encoding('BINARY'),  # blob
  IPAddr.new('192.168.1.1'),
  BigDecimal('123.456')
)
```

### Collection Types

```ruby
# Create table with collections
session.execute(<<-CQL)
  CREATE TABLE IF NOT EXISTS collections_example (
    id UUID PRIMARY KEY,
    tags SET<TEXT>,
    scores LIST<INT>,
    attributes MAP<TEXT, TEXT>,
    nested MAP<TEXT, FROZEN<LIST<INT>>>
  )
CQL

# Working with sets
session.execute(
  "INSERT INTO collections_example (id, tags) VALUES (?, ?)",
  CassandraCpp::Uuid.generate,
  Set.new(['ruby', 'cassandra', 'database'])
)

# Update set
session.execute(
  "UPDATE collections_example SET tags = tags + ? WHERE id = ?",
  Set.new(['performance']),
  collection_id
)

# Working with lists
session.execute(
  "INSERT INTO collections_example (id, scores) VALUES (?, ?)",
  CassandraCpp::Uuid.generate,
  [100, 95, 87, 92]
)

# Append to list
session.execute(
  "UPDATE collections_example SET scores = scores + ? WHERE id = ?",
  [88],
  collection_id
)

# Working with maps
session.execute(
  "INSERT INTO collections_example (id, attributes) VALUES (?, ?)",
  CassandraCpp::Uuid.generate,
  {'color' => 'blue', 'size' => 'large', 'weight' => '150kg'}
)

# Update map entries
session.execute(
  "UPDATE collections_example SET attributes = attributes + ? WHERE id = ?",
  {'color' => 'red', 'material' => 'steel'},
  collection_id
)
```

### User-Defined Types (UDT)

```ruby
# Create a UDT
session.execute(<<-CQL)
  CREATE TYPE IF NOT EXISTS address (
    street TEXT,
    city TEXT,
    state TEXT,
    zip_code TEXT,
    country TEXT
  )
CQL

# Create table using UDT
session.execute(<<-CQL)
  CREATE TABLE IF NOT EXISTS users_with_address (
    id UUID PRIMARY KEY,
    name TEXT,
    home_address FROZEN<address>,
    work_address FROZEN<address>
  )
CQL

# Insert with UDT
home_address = {
  street: '123 Main St',
  city: 'San Francisco',
  state: 'CA',
  zip_code: '94105',
  country: 'USA'
}

session.execute(
  "INSERT INTO users_with_address (id, name, home_address) VALUES (?, ?, ?)",
  CassandraCpp::Uuid.generate,
  'John Doe',
  home_address
)
```

## Result Handling

### Iterating Results

```ruby
# Basic iteration
result = session.execute('SELECT * FROM users')

# Using each
result.each do |row|
  puts "User: #{row['name']}, Email: #{row['email']}"
end

# Convert to array
users = result.to_a

# Access by index
first_user = result.first
last_user = result.last

# Check if empty
if result.empty?
  puts 'No users found'
end

# Get count (for small result sets)
puts "Found #{result.size} users"
```

### Accessing Column Data

```ruby
result = session.execute('SELECT * FROM users WHERE id = ?', user_id)
row = result.first

# Access by string key
email = row['email']
name = row['name']

# Access by symbol (if configured)
email = row[:email]
name = row[:name]

# Get all column names
columns = row.keys

# Get all values
values = row.values

# Convert to hash
user_hash = row.to_h
```

### Handling Large Result Sets

```ruby
# Use paging for large results
statement = session.prepare('SELECT * FROM large_table')
options = { page_size: 1000 }

# Automatic paging
session.execute(statement, options: options).each do |row|
  # Process row - driver handles paging automatically
  process_row(row)
end

# Manual paging control
result = session.execute(statement, options: { page_size: 100 })
loop do
  result.each { |row| process_row(row) }
  
  break unless result.has_more_pages?
  result = result.next_page
end

# Stream processing pattern
def process_in_batches(session, query, batch_size: 1000)
  offset = 0
  loop do
    result = session.execute("#{query} LIMIT #{batch_size}", options: { page_size: batch_size })
    
    break if result.empty?
    
    yield result.to_a
    
    offset += batch_size
  end
end
```

## Error Management

### Basic Error Handling

```ruby
begin
  result = session.execute('SELECT * FROM users')
rescue CassandraCpp::Errors::NoHostsAvailable => e
  # Handle connection errors
  logger.error "No Cassandra hosts available: #{e.message}"
  retry_connection
rescue CassandraCpp::Errors::QueryError => e
  # Handle query errors
  logger.error "Query failed: #{e.message}"
  logger.error "Error code: #{e.code}"
rescue CassandraCpp::Errors::TimeoutError => e
  # Handle timeouts
  logger.error "Query timed out: #{e.message}"
  retry_with_backoff
rescue => e
  # Handle unexpected errors
  logger.error "Unexpected error: #{e.class} - #{e.message}"
  raise
end
```

### Common Error Types

```ruby
# Connection errors
begin
  cluster.connect
rescue CassandraCpp::Errors::NoHostsAvailable => e
  e.errors.each do |host, error|
    puts "Host #{host} failed: #{error}"
  end
end

# Authentication errors
begin
  cluster.connect
rescue CassandraCpp::Errors::AuthenticationError => e
  puts "Authentication failed: #{e.message}"
end

# Query validation errors
begin
  session.execute('INVALID QUERY')
rescue CassandraCpp::Errors::SyntaxError => e
  puts "Invalid CQL: #{e.message}"
end

# Timeout errors
begin
  session.execute('SELECT * FROM large_table', timeout: 1)
rescue CassandraCpp::Errors::TimeoutError => e
  puts "Query timed out after #{e.timeout}ms"
end

# Write errors
begin
  session.execute('INSERT INTO users (id) VALUES (?)', nil)
rescue CassandraCpp::Errors::InvalidError => e
  puts "Invalid value: #{e.message}"
end
```

### Retry Strategies

```ruby
class RetryableQuery
  MAX_RETRIES = 3
  RETRY_DELAY = 0.1  # seconds
  
  def self.execute(session, query, *args)
    retries = 0
    
    begin
      session.execute(query, *args)
    rescue CassandraCpp::Errors::TimeoutError, 
           CassandraCpp::Errors::UnavailableError => e
      retries += 1
      
      if retries <= MAX_RETRIES
        sleep(RETRY_DELAY * retries)  # Exponential backoff
        retry
      else
        raise
      end
    end
  end
end

# Usage
result = RetryableQuery.execute(
  session,
  'SELECT * FROM users WHERE id = ?',
  user_id
)
```

## Connection Lifecycle

### Proper Resource Management

```ruby
# Good: Create cluster once, reuse sessions
class CassandraConnection
  attr_reader :cluster, :session
  
  def initialize(config)
    @cluster = CassandraCpp::Cluster.build(config)
    @session = @cluster.connect
  end
  
  def close
    @session.close if @session
    @cluster.close if @cluster
  end
end

# Use in application
connection = CassandraConnection.new(hosts: ['localhost'])
begin
  connection.session.execute('SELECT * FROM users')
ensure
  connection.close
end
```

### Connection Monitoring

```ruby
# Monitor connection health
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['localhost']
  
  # Add event listeners
  config.on(:host_up) do |host|
    logger.info "Host available: #{host}"
  end
  
  config.on(:host_down) do |host|
    logger.warn "Host unavailable: #{host}"
  end
  
  config.on(:connection_created) do |connection|
    logger.debug "New connection: #{connection}"
  end
end

# Check cluster status
if cluster.connected?
  puts "Cluster is connected"
  puts "Connected to #{cluster.hosts.size} hosts"
end
```

## Batch Operations

### Logged Batches

```ruby
# Create a logged batch (atomic)
batch = session.batch do |b|
  b.add("INSERT INTO users (id, name) VALUES (?, ?)", 
        CassandraCpp::Uuid.generate, 'User 1')
  b.add("INSERT INTO users (id, name) VALUES (?, ?)", 
        CassandraCpp::Uuid.generate, 'User 2')
  b.add("UPDATE users SET age = ? WHERE id = ?", 
        30, existing_user_id)
end

# Execute the batch
session.execute(batch)

# Or use block form for immediate execution
session.batch do |b|
  100.times do |i|
    b.add("INSERT INTO users (id, name, email) VALUES (?, ?, ?)",
          CassandraCpp::Uuid.generate,
          "User #{i}",
          "user#{i}@example.com")
  end
end
```

### Unlogged Batches

```ruby
# Unlogged batch for performance (no atomicity guarantee)
batch = session.unlogged_batch do |b|
  # Multiple inserts to the same partition
  user_id = CassandraCpp::Uuid.generate
  b.add("INSERT INTO user_activities (user_id, activity_id, timestamp) VALUES (?, ?, ?)",
        user_id, CassandraCpp::Uuid.generate, Time.now)
  b.add("INSERT INTO user_activities (user_id, activity_id, timestamp) VALUES (?, ?, ?)",
        user_id, CassandraCpp::Uuid.generate, Time.now + 1)
end

session.execute(batch)
```

### Counter Batches

```ruby
# Batch counter updates
session.batch(:counter) do |b|
  b.add("UPDATE page_views SET count = count + ? WHERE page_id = ?", 1, page1_id)
  b.add("UPDATE page_views SET count = count + ? WHERE page_id = ?", 1, page2_id)
  b.add("UPDATE page_views SET count = count + ? WHERE page_id = ?", 1, page3_id)
end
```

## Consistency Levels

### Setting Consistency

```ruby
# Per-query consistency
session.execute(
  'SELECT * FROM users',
  consistency: :quorum
)

# Available consistency levels:
# :any, :one, :two, :three, :quorum, :all,
# :local_quorum, :each_quorum, :serial, :local_serial, :local_one

# Set default consistency
session.default_consistency = :local_quorum

# For writes with high availability
session.execute(
  'INSERT INTO users (id, name) VALUES (?, ?)',
  CassandraCpp::Uuid.generate,
  'John Doe',
  consistency: :local_one
)

# For strong consistency reads
session.execute(
  'SELECT * FROM users WHERE id = ?',
  user_id,
  consistency: :local_quorum
)
```

### Serial Consistency

```ruby
# For lightweight transactions
result = session.execute(
  'INSERT INTO users (id, email) VALUES (?, ?) IF NOT EXISTS',
  CassandraCpp::Uuid.generate,
  'unique@example.com',
  consistency: :quorum,
  serial_consistency: :serial
)

if result.first['[applied]']
  puts 'User created successfully'
else
  puts 'User already exists'
end
```

## Common Patterns

### Repository Pattern

```ruby
class UserRepository
  def initialize(session)
    @session = session
    prepare_statements
  end
  
  def find(id)
    result = @session.execute(@find_stmt.bind(id))
    result.first
  end
  
  def create(attributes)
    id = CassandraCpp::Uuid.generate
    @session.execute(
      @insert_stmt.bind(
        id,
        attributes[:email],
        attributes[:name],
        attributes[:age],
        Time.now
      )
    )
    id
  end
  
  def update(id, attributes)
    @session.execute(
      @update_stmt.bind(
        attributes[:name],
        attributes[:age],
        Time.now,
        id
      )
    )
  end
  
  def delete(id)
    @session.execute(@delete_stmt.bind(id))
  end
  
  def find_by_email(email)
    result = @session.execute(@find_by_email_stmt.bind(email))
    result.first
  end
  
  private
  
  def prepare_statements
    @find_stmt = @session.prepare(
      'SELECT * FROM users WHERE id = ?'
    )
    @insert_stmt = @session.prepare(
      'INSERT INTO users (id, email, name, age, created_at) VALUES (?, ?, ?, ?, ?)'
    )
    @update_stmt = @session.prepare(
      'UPDATE users SET name = ?, age = ?, updated_at = ? WHERE id = ?'
    )
    @delete_stmt = @session.prepare(
      'DELETE FROM users WHERE id = ?'
    )
    @find_by_email_stmt = @session.prepare(
      'SELECT * FROM users WHERE email = ? ALLOW FILTERING'
    )
  end
end

# Usage
repo = UserRepository.new(session)
user_id = repo.create(email: 'test@example.com', name: 'Test User', age: 25)
user = repo.find(user_id)
```

### Connection Helper

```ruby
module CassandraHelper
  extend self
  
  def with_session(keyspace = nil)
    cluster = CassandraCpp::Cluster.build do |config|
      config.hosts = ENV.fetch('CASSANDRA_HOSTS', 'localhost').split(',')
      config.compression = :lz4
    end
    
    session = keyspace ? cluster.connect(keyspace) : cluster.connect
    
    yield session
  ensure
    session&.close
    cluster&.close
  end
  
  def with_retries(max_retries: 3, delay: 0.1)
    retries = 0
    begin
      yield
    rescue CassandraCpp::Errors::TimeoutError => e
      retries += 1
      if retries <= max_retries
        sleep(delay * retries)
        retry
      else
        raise
      end
    end
  end
end

# Usage
CassandraHelper.with_session('my_keyspace') do |session|
  CassandraHelper.with_retries do
    session.execute('SELECT * FROM users')
  end
end
```

## Next Steps

- [ORM Models](04_orm_models.md) - Learn about the ActiveRecord-style ORM
- [Advanced Queries](05_queries.md) - Complex querying techniques
- [Performance](07_performance.md) - Optimize your queries
- [Advanced Features](08_advanced_features.md) - Async operations and more