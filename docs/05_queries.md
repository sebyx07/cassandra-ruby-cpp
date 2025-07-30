# Query Guide

This guide covers the powerful querying capabilities of Cassandra-CPP, from basic queries to advanced techniques. Learn how to efficiently retrieve data using both the ORM query interface and raw CQL.

## Table of Contents

- [Query Basics](#query-basics)
- [Query Interface](#query-interface)
- [Filtering](#filtering)
- [Sorting](#sorting)
- [Pagination](#pagination)
- [Aggregations](#aggregations)
- [Raw CQL Queries](#raw-cql-queries)
- [Prepared Statements](#prepared-statements)
- [Query Optimization](#query-optimization)
- [Advanced Query Patterns](#advanced-query-patterns)

## Query Basics

### Simple Queries

```ruby
# Find by primary key
user = User.find('550e8400-e29b-41d4-a716-446655440000')

# Find multiple by primary keys
users = User.find(['id1', 'id2', 'id3'])

# Find first record
first_user = User.first

# Find all records (use with caution!)
all_users = User.all

# Check existence
User.exists?('550e8400-e29b-41d4-a716-446655440000')  # => true/false

# Count records
total_users = User.count
```

### Find Methods

```ruby
# find - raises exception if not found
user = User.find('550e8400-e29b-41d4-a716-446655440000')
# => CassandraCpp::RecordNotFound if not exists

# find_by - returns nil if not found
user = User.find_by(email: 'john@example.com')
# => nil if not exists

# find_by! - raises exception if not found
user = User.find_by!(email: 'john@example.com')
# => CassandraCpp::RecordNotFound if not exists

# find_or_create_by
user = User.find_or_create_by(email: 'new@example.com') do |u|
  u.name = 'New User'
  u.age = 25
end

# find_or_initialize_by
user = User.find_or_initialize_by(email: 'new@example.com')
user.new_record?  # => true if not found
```

## Query Interface

### Chainable Query Methods

```ruby
# Queries are lazy-loaded and chainable
users = User
  .where(status: 'active')
  .where('age > ?', 18)
  .order(created_at: :desc)
  .limit(10)

# Query is executed when you access the results
users.each { |user| puts user.name }  # Executes here
users.to_a                             # Or here
users.first                            # Or here
```

### Select Specific Columns

```ruby
# Select only needed columns for performance
users = User.select(:id, :name, :email).where(status: 'active')

# Dynamic column selection
columns = [:id, :name]
columns << :email if include_email?
User.select(*columns).all

# Exclude columns
User.select_all.except(:password_digest, :secret_token)
```

### Distinct Queries

```ruby
# Get distinct values
countries = User.distinct.pluck(:country)

# Distinct with specific columns
User.select(:country, :city).distinct

# Count distinct
unique_countries = User.distinct.count(:country)
```

## Filtering

### Where Conditions

```ruby
# Equality
User.where(status: 'active')
User.where(age: 25)

# Multiple conditions (AND)
User.where(status: 'active', age: 25)

# Hash syntax with arrays (IN query)
User.where(status: ['active', 'pending'])
User.where(id: [id1, id2, id3])

# String conditions
User.where('age > ?', 18)
User.where('age >= ? AND age <= ?', 18, 65)
User.where('created_at > ?', 1.week.ago)

# Named placeholders
User.where('age > :min_age AND age < :max_age', min_age: 18, max_age: 65)

# ALLOW FILTERING (use with caution!)
User.where(email: 'john@example.com').allow_filtering
```

### Range Queries

```ruby
# Range conditions for clustering columns
UserActivity
  .where(user_id: user_id)
  .where(activity_date: Date.today..Date.tomorrow)

# Time ranges
Event
  .where(timestamp: 1.hour.ago..Time.now)
  .order(timestamp: :desc)

# Numeric ranges
Product.where(price: 10.00..100.00).allow_filtering

# Open-ended ranges
User.where(age: 18..).allow_filtering      # age >= 18
User.where(age: ..65).allow_filtering      # age <= 65
```

### Complex Conditions

```ruby
# OR conditions (requires ALLOW FILTERING or secondary index)
User.where('status = ? OR status = ?', 'active', 'pending').allow_filtering

# NOT conditions
User.where.not(status: 'deleted')
User.where.not(age: 18..25)

# Combining conditions
User
  .where(status: 'active')
  .where.not(country: 'US')
  .where('age > ?', 18)
  .allow_filtering

# Null checks
User.where(email: nil)
User.where.not(email: nil)
```

### Token-Based Filtering

```ruby
# For efficient full table scans
last_token = nil

loop do
  query = User.limit(1000)
  query = query.where("token(id) > ?", last_token) if last_token
  
  results = query.to_a
  break if results.empty?
  
  results.each { |user| process(user) }
  last_token = results.last.token(:id)
end
```

## Sorting

### Order By

```ruby
# Single column ordering
User.order(:created_at)        # Default ascending
User.order(created_at: :asc)   # Explicit ascending
User.order(created_at: :desc)  # Descending

# Multiple column ordering
UserActivity
  .where(user_id: user_id)
  .order(activity_date: :desc, created_at: :desc)

# Dynamic ordering
sort_column = params[:sort] || 'created_at'
sort_direction = params[:direction] || 'desc'
User.order(sort_column => sort_direction)

# Reverse ordering
User.order(:created_at).reverse_order
```

### Clustering Order

```ruby
# Define default clustering order in model
class TimeSeries < CassandraCpp::Model
  column :device_id, :text, partition_key: true
  column :timestamp, :timestamp, clustering_key: true
  column :value, :float
  
  clustering_order timestamp: :desc
end

# Query respects clustering order
TimeSeries.where(device_id: 'sensor-1').limit(10)
# Returns 10 most recent readings
```

## Pagination

### Limit and Offset

```ruby
# Basic limit
recent_users = User.order(created_at: :desc).limit(10)

# Offset (Note: Cassandra doesn't support OFFSET natively)
# This is emulated and can be inefficient
User.limit(10).offset(20)

# Better: Use token-based pagination
page_size = 20
last_id = params[:last_id]

users = User.limit(page_size)
users = users.where("token(id) > token(?)", last_id) if last_id
```

### Page-Based Pagination

```ruby
# Using the paginate helper
class User < CassandraCpp::Model
  include CassandraCpp::Pagination
  
  self.per_page = 25
end

# Get page 2 with 25 records per page
users = User.paginate(page: 2)
users.total_pages
users.current_page
users.next_page
users.previous_page

# Custom page size
users = User.paginate(page: 1, per_page: 50)

# With conditions
active_users = User
  .where(status: 'active')
  .order(created_at: :desc)
  .paginate(page: params[:page])
```

### Cursor-Based Pagination

```ruby
# More efficient for large datasets
class CursorPaginator
  def initialize(scope, per_page: 100)
    @scope = scope
    @per_page = per_page
  end
  
  def page(cursor = nil)
    query = @scope.limit(@per_page + 1)
    
    if cursor
      # Decode cursor to get last record values
      last_values = decode_cursor(cursor)
      query = apply_cursor_conditions(query, last_values)
    end
    
    results = query.to_a
    has_more = results.size > @per_page
    results = results.take(@per_page)
    
    {
      data: results,
      has_more: has_more,
      cursor: has_more ? encode_cursor(results.last) : nil
    }
  end
  
  private
  
  def encode_cursor(record)
    Base64.urlsafe_encode64(record.id.to_s)
  end
  
  def decode_cursor(cursor)
    Base64.urlsafe_decode64(cursor)
  end
  
  def apply_cursor_conditions(query, last_id)
    query.where("token(id) > token(?)", last_id)
  end
end

# Usage
paginator = CursorPaginator.new(User.where(status: 'active'))
result = paginator.page(params[:cursor])
```

## Aggregations

### Count

```ruby
# Count all records
total = User.count

# Count with conditions
active_count = User.where(status: 'active').count

# Count specific column (non-null values)
email_count = User.count(:email)

# Count distinct
unique_countries = User.distinct.count(:country)

# Group and count
User.group(:country).count
# => { 'US' => 150, 'UK' => 75, 'CA' => 50 }
```

### Min/Max/Sum/Avg

```ruby
# Aggregation functions
Order.sum(:total)          # Sum of all totals
Order.average(:total)      # Average total
Order.minimum(:total)      # Minimum total
Order.maximum(:total)      # Maximum total

# With conditions
Order
  .where(status: 'completed')
  .where(created_at: Date.today.beginning_of_day..Date.today.end_of_day)
  .sum(:total)

# Multiple aggregations
stats = Order.aggregate(
  total_sum: { sum: :total },
  avg_total: { avg: :total },
  max_total: { max: :total },
  order_count: { count: '*' }
)
```

### Group By

```ruby
# Group by single column
User.group(:country).count

# Group by multiple columns
Order
  .group(:status, :payment_method)
  .count

# Group with aggregations
Order
  .group(:customer_id)
  .aggregate(
    total_spent: { sum: :total },
    order_count: { count: '*' },
    avg_order: { avg: :total }
  )

# Having clause (filter groups)
User
  .group(:country)
  .having('count(*) > ?', 100)
  .count
```

## Raw CQL Queries

### Execute Raw CQL

```ruby
# Simple raw query
results = User.execute("SELECT * FROM users WHERE status = 'active'")

# With parameters
results = User.execute(
  "SELECT * FROM users WHERE age > ? AND country = ?",
  18,
  'US'
)

# Process results
results.each do |row|
  puts "#{row['name']} - #{row['email']}"
end

# Return model instances
users = User.from_cql(
  "SELECT * FROM users WHERE status = ?",
  'active'
)
```

### Complex CQL Queries

```ruby
# Using CQL functions
results = User.execute(<<-CQL, user_id)
  SELECT id, name, email,
         toTimestamp(created_at) as created_timestamp,
         TTL(email) as email_ttl,
         WRITETIME(email) as email_write_time
  FROM users
  WHERE id = ?
CQL

# JSON queries
User.execute(<<-CQL)
  SELECT JSON * FROM users WHERE status = 'active'
CQL

# Token queries for pagination
User.execute(<<-CQL, last_token, limit)
  SELECT * FROM users 
  WHERE token(id) > ? 
  LIMIT ?
CQL
```

### CQL Injection Prevention

```ruby
# Bad - vulnerable to CQL injection
status = params[:status]
User.execute("SELECT * FROM users WHERE status = '#{status}'")

# Good - use parameterized queries
User.execute("SELECT * FROM users WHERE status = ?", params[:status])

# Good - use named parameters
User.execute(
  "SELECT * FROM users WHERE status = :status AND age > :age",
  status: params[:status],
  age: 18
)

# Safe dynamic column names
allowed_columns = %w[name email created_at]
column = params[:sort_by]

if allowed_columns.include?(column)
  User.execute("SELECT * FROM users ORDER BY #{column}")
else
  raise "Invalid column name"
end
```

## Prepared Statements

### Basic Prepared Statements

```ruby
# Prepare a statement
statement = session.prepare(
  'SELECT * FROM users WHERE email = ?'
)

# Execute with parameters
result = session.execute(statement.bind('john@example.com'))

# Reuse prepared statements
emails = ['john@example.com', 'jane@example.com', 'bob@example.com']
results = emails.map do |email|
  session.execute(statement.bind(email))
end
```

### Model-Level Prepared Statements

```ruby
class User < CassandraCpp::Model
  # Define prepared statements
  prepare :find_by_email, 
          'SELECT * FROM users WHERE email = ? ALLOW FILTERING'
  
  prepare :find_active_by_country,
          'SELECT * FROM users WHERE country = ? AND status = ? ALLOW FILTERING'
  
  prepare :update_last_login,
          'UPDATE users SET last_login = ? WHERE id = ?'
  
  # Use prepared statements
  def self.by_email(email)
    execute_prepared(:find_by_email, email).first
  end
  
  def self.active_in_country(country)
    execute_prepared(:find_active_by_country, country, 'active')
  end
  
  def update_last_login!
    self.class.execute_prepared(:update_last_login, Time.now, id)
  end
end
```

### Automatic Statement Preparation

```ruby
class User < CassandraCpp::Model
  # Enable automatic preparation of all queries
  auto_prepare_statements true
  
  # Queries are automatically prepared on first use
  # and cached for subsequent calls
end

# These queries will be automatically prepared
User.where(email: 'john@example.com')
User.find('550e8400-e29b-41d4-a716-446655440000')
```

## Query Optimization

### Using Secondary Indexes

```ruby
# Create secondary index
class User < CassandraCpp::Model
  column :email, :text, index: true
  column :country, :text, index: true
  column :status, :text
  
  # Composite index
  index [:country, :status], name: 'country_status_idx'
end

# Efficient queries using indexes
User.where(email: 'john@example.com')
User.where(country: 'US')
User.where(country: 'US', status: 'active')

# Force index usage
User.use_index('country_status_idx').where(country: 'US', status: 'active')
```

### Query Plan Analysis

```ruby
# Explain query execution
plan = User.where(status: 'active').explain

puts plan.estimated_rows
puts plan.uses_index?
puts plan.requires_filtering?
puts plan.partition_key_restrictions

# Trace query execution
User.where(email: 'john@example.com').trace do |trace|
  puts "Query took #{trace.duration}ms"
  trace.events.each do |event|
    puts "#{event.source}: #{event.activity} (#{event.duration}μs)"
  end
end
```

### Batch Reading

```ruby
# Efficient batch reading
def read_in_batches(model, batch_size: 1000)
  last_token = nil
  
  loop do
    query = model.limit(batch_size)
    query = query.where("token(id) > ?", last_token) if last_token
    
    batch = query.to_a
    break if batch.empty?
    
    yield batch
    
    last_token = batch.last.token(:id)
  end
end

# Usage
read_in_batches(User, batch_size: 5000) do |users|
  users.each { |user| process_user(user) }
end
```

## Advanced Query Patterns

### Time Series Queries

```ruby
class SensorReading < CassandraCpp::Model
  column :sensor_id, :text, partition_key: true
  column :timestamp, :timestamp, clustering_key: true
  column :temperature, :float
  column :humidity, :float
  
  clustering_order timestamp: :desc
  
  # Get latest reading
  def self.latest_for_sensor(sensor_id)
    where(sensor_id: sensor_id).first
  end
  
  # Get readings for time range
  def self.for_period(sensor_id, start_time, end_time)
    where(sensor_id: sensor_id)
      .where(timestamp: start_time..end_time)
      .order(timestamp: :asc)
  end
  
  # Downsample readings
  def self.downsample(sensor_id, start_time, end_time, interval = 1.hour)
    readings = for_period(sensor_id, start_time, end_time)
    
    readings.group_by { |r| r.timestamp.to_i / interval }.map do |_, group|
      {
        timestamp: Time.at(group.first.timestamp.to_i / interval * interval),
        temperature: group.map(&:temperature).sum / group.size,
        humidity: group.map(&:humidity).sum / group.size
      }
    end
  end
end
```

### Hierarchical Data

```ruby
class Category < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :parent_id, :uuid
  column :name, :text
  column :path, :list, of: :uuid  # Materialized path
  
  # Get all children
  def children
    self.class.where(parent_id: id)
  end
  
  # Get all descendants
  def descendants
    self.class.where('path CONTAINS ?', id).allow_filtering
  end
  
  # Get ancestors
  def ancestors
    return [] if path.empty?
    self.class.find(path)
  end
  
  # Build tree structure
  def self.build_tree(parent_id = nil)
    nodes = where(parent_id: parent_id)
    
    nodes.map do |node|
      {
        node: node,
        children: build_tree(node.id)
      }
    end
  end
end
```

### Full-Text Search

```ruby
class Document < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :title, :text
  column :content, :text
  column :search_terms, :set, of: :text  # Indexed terms
  
  # Create search index
  index :search_terms
  
  # Index document for search
  before_save :index_for_search
  
  def index_for_search
    terms = Set.new
    
    # Extract terms from title
    terms.merge(title.downcase.split(/\W+/))
    
    # Extract terms from content
    terms.merge(content.downcase.split(/\W+/).uniq.take(100))
    
    # Remove stop words
    stop_words = %w[the a an and or but in on at to for]
    terms.subtract(stop_words)
    
    self.search_terms = terms
  end
  
  # Search documents
  def self.search(query)
    terms = query.downcase.split(/\W+/)
    
    # Find documents containing any term
    where(search_terms: terms).allow_filtering
  end
  
  # Ranked search
  def self.ranked_search(query)
    terms = query.downcase.split(/\W+/)
    
    results = search(query).map do |doc|
      # Calculate relevance score
      score = terms.count { |term| doc.search_terms.include?(term) }
      score += 2 if doc.title.downcase.include?(query.downcase)
      
      { document: doc, score: score }
    end
    
    results.sort_by { |r| -r[:score] }.map { |r| r[:document] }
  end
end
```

### Geospatial Queries

```ruby
class Location < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :latitude, :float
  column :longitude, :float
  column :geohash, :text, index: true  # For proximity queries
  
  before_save :calculate_geohash
  
  # Find locations within radius
  def self.within_radius(lat, lng, radius_km)
    # Calculate geohash precision based on radius
    precision = case radius_km
                when 0..1 then 7
                when 1..5 then 6
                when 5..20 then 5
                else 4
                end
    
    center_geohash = encode_geohash(lat, lng, precision)
    
    # Get neighboring geohashes
    geohashes = [center_geohash] + neighbors(center_geohash)
    
    # Query with geohash prefix
    locations = where(geohash: geohashes.map { |gh| "#{gh}*" })
    
    # Filter by exact distance
    locations.select do |location|
      distance = haversine_distance(
        lat, lng,
        location.latitude, location.longitude
      )
      distance <= radius_km
    end
  end
  
  private
  
  def calculate_geohash
    self.geohash = self.class.encode_geohash(latitude, longitude)
  end
  
  def self.encode_geohash(lat, lng, precision = 12)
    # Geohash encoding implementation
    # ...
  end
  
  def self.haversine_distance(lat1, lng1, lat2, lng2)
    # Haversine formula implementation
    # ...
  end
end
```

### Faceted Search

```ruby
class Product < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :category, :text
  column :brand, :text
  column :price, :decimal
  column :attributes, :map, of: [:text, :text]
  column :tags, :set, of: :text
  
  # Indexes for faceting
  index :category
  index :brand
  index :tags
  
  # Faceted search with counts
  def self.faceted_search(filters = {})
    base_query = self
    
    # Apply filters
    filters.each do |field, value|
      base_query = base_query.where(field => value)
    end
    
    # Get facet counts
    facets = {}
    
    # Category facets
    facets[:categories] = base_query
      .group(:category)
      .count
      .transform_values { |count| { count: count } }
    
    # Brand facets
    facets[:brands] = base_query
      .group(:brand)
      .count
      .transform_values { |count| { count: count } }
    
    # Price range facets
    facets[:price_ranges] = {
      'Under $25' => base_query.where(price: 0..25).count,
      '$25-$50' => base_query.where(price: 25..50).count,
      '$50-$100' => base_query.where(price: 50..100).count,
      'Over $100' => base_query.where('price > ?', 100).count
    }
    
    {
      results: base_query.limit(20),
      facets: facets,
      total: base_query.count
    }
  end
end
```

## Query Best Practices

### 1. Design Queries First

```ruby
# Design your data model around your queries
class UserActivity < CassandraCpp::Model
  # Partition by user for "activities by user" queries
  column :user_id, :uuid, partition_key: true
  column :activity_time, :timestamp, clustering_key: true
  column :activity_id, :uuid, clustering_key: true
  
  # Efficient query
  def self.recent_for_user(user_id, limit = 10)
    where(user_id: user_id)
      .order(activity_time: :desc)
      .limit(limit)
  end
end
```

### 2. Avoid ALLOW FILTERING

```ruby
# Bad: Requires full table scan
User.where(email: 'john@example.com').allow_filtering

# Good: Use secondary index
class User < CassandraCpp::Model
  column :email, :text, index: true
end
User.where(email: 'john@example.com')

# Better: Design table for query pattern
class UserByEmail < CassandraCpp::Model
  column :email, :text, partition_key: true
  column :user_id, :uuid
  # ... denormalized user data
end
```

### 3. Batch Operations Carefully

```ruby
# Good: Batch operations on same partition
UserActivity.batch do
  activities.each do |activity|
    UserActivity.create!(
      user_id: user_id,  # Same partition
      activity_time: activity[:time],
      activity_id: CassandraCpp::Uuid.generate
    )
  end
end

# Bad: Batch across partitions
User.batch do
  users.each do |user_data|
    User.create!(user_data)  # Different partitions
  end
end
```

## Next Steps

- [Migrations](06_migrations.md) - Managing schema changes
- [Performance](07_performance.md) - Query optimization techniques
- [Advanced Features](08_advanced_features.md) - Async queries and more