# ORM Models Guide

Cassandra-CPP provides a powerful ActiveRecord-inspired ORM that combines the familiarity of Ruby patterns with the performance of native C++ bindings. This guide covers everything you need to know about defining and working with models.

## Table of Contents

- [Defining Models](#defining-models)
- [Model Attributes](#model-attributes)
- [Primary Keys](#primary-keys)
- [Validations](#validations)
- [Associations](#associations)
- [Callbacks](#callbacks)
- [Inheritance](#inheritance)
- [Custom Type Handling](#custom-type-handling)
- [Model Configuration](#model-configuration)
- [Advanced Features](#advanced-features)

## Defining Models

### Basic Model Definition

```ruby
class User < CassandraCpp::Model
  # Specify the table name (optional, defaults to pluralized class name)
  table_name 'users'
  
  # Define columns
  column :id, :uuid, primary_key: true
  column :email, :text
  column :name, :text
  column :age, :int
  column :active, :boolean, default: true
  column :created_at, :timestamp
  column :updated_at, :timestamp
end
```

### Creating Tables from Models

```ruby
# Generate CREATE TABLE statement
puts User.create_table_cql
# => CREATE TABLE IF NOT EXISTS users (
#      id UUID PRIMARY KEY,
#      email TEXT,
#      name TEXT,
#      age INT,
#      active BOOLEAN,
#      created_at TIMESTAMP,
#      updated_at TIMESTAMP
#    )

# Create the table in Cassandra
User.create_table!

# With custom options
User.create_table!(
  if_not_exists: true,
  compression: {
    'sstable_compression' => 'LZ4Compressor',
    'chunk_length_kb' => 64
  },
  gc_grace_seconds: 864000
)
```

### Compound Primary Keys

```ruby
class UserActivity < CassandraCpp::Model
  table_name 'user_activities'
  
  # Partition key
  column :user_id, :uuid, partition_key: true
  
  # Clustering columns
  column :activity_date, :date, clustering_key: true
  column :activity_id, :timeuuid, clustering_key: true
  
  # Regular columns
  column :activity_type, :text
  column :details, :text
  
  # Define clustering order
  clustering_order :activity_date, :desc
  clustering_order :activity_id, :desc
end

# Alternative syntax
class OrderItem < CassandraCpp::Model
  table_name 'order_items'
  
  # Composite partition key
  primary_key [:order_id, :customer_id], [:item_id, :created_at]
  
  column :order_id, :uuid
  column :customer_id, :uuid
  column :item_id, :uuid
  column :created_at, :timestamp
  column :quantity, :int
  column :price, :decimal
end
```

## Model Attributes

### Column Types

```ruby
class DataTypesExample < CassandraCpp::Model
  # Numeric types
  column :int_value, :int                    # 32-bit signed
  column :bigint_value, :bigint              # 64-bit signed
  column :smallint_value, :smallint          # 16-bit signed
  column :tinyint_value, :tinyint            # 8-bit signed
  column :float_value, :float                # 32-bit float
  column :double_value, :double              # 64-bit float
  column :decimal_value, :decimal            # Variable precision
  column :varint_value, :varint              # Arbitrary precision
  
  # Text types
  column :text_value, :text                  # UTF-8 string
  column :varchar_value, :varchar            # Same as text
  column :ascii_value, :ascii                # ASCII string
  
  # UUID types
  column :uuid_value, :uuid                  # Type 4 UUID
  column :timeuuid_value, :timeuuid          # Type 1 UUID
  
  # Date/Time types
  column :timestamp_value, :timestamp        # Millisecond precision
  column :date_value, :date                  # Date without time
  column :time_value, :time                  # Time without date
  column :duration_value, :duration          # Time duration
  
  # Binary types
  column :blob_value, :blob                  # Binary data
  
  # Other types
  column :boolean_value, :boolean            # true/false
  column :inet_value, :inet                  # IP address
  column :counter_value, :counter            # Counter column
end
```

### Collection Types

```ruby
class CollectionExample < CassandraCpp::Model
  # Set - unique values, no order
  column :tags, :set, of: :text
  column :follower_ids, :set, of: :uuid
  
  # List - ordered, allows duplicates
  column :scores, :list, of: :int
  column :events, :list, of: :timestamp
  
  # Map - key-value pairs
  column :attributes, :map, of: [:text, :text]
  column :settings, :map, of: [:text, :int]
  
  # Frozen collections (for use in primary keys)
  column :categories, :frozen_set, of: :text
  column :metadata, :frozen_map, of: [:text, :text]
  
  # Nested collections
  column :nested_data, :map, of: [:text, [:list, :int]]
end

# Usage
model = CollectionExample.new
model.tags = Set.new(['ruby', 'cassandra'])
model.scores = [100, 95, 87]
model.attributes = { 'color' => 'blue', 'size' => 'large' }
```

### User-Defined Types

```ruby
# Define a UDT
class Address < CassandraCpp::UserType
  field :street, :text
  field :city, :text
  field :state, :text
  field :zip_code, :text
  field :country, :text
end

# Use in a model
class Customer < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :email, :text
  column :home_address, :frozen, of: Address
  column :work_address, :frozen, of: Address
  column :addresses, :map, of: [:text, Address]
end

# Usage
customer = Customer.new
customer.home_address = Address.new(
  street: '123 Main St',
  city: 'San Francisco',
  state: 'CA',
  zip_code: '94105',
  country: 'USA'
)
```

### Default Values

```ruby
class Post < CassandraCpp::Model
  column :id, :uuid, primary_key: true, default: -> { CassandraCpp::Uuid.generate }
  column :title, :text
  column :content, :text
  column :status, :text, default: 'draft'
  column :views, :counter, default: 0
  column :published, :boolean, default: false
  column :created_at, :timestamp, default: -> { Time.now }
  column :tags, :set, of: :text, default: -> { Set.new }
end
```

## Primary Keys

### Simple Primary Key

```ruby
class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :email, :text
end
```

### Composite Primary Key

```ruby
class UserSession < CassandraCpp::Model
  # Method 1: Individual column definitions
  column :user_id, :uuid, partition_key: true
  column :session_id, :timeuuid, clustering_key: true
  column :created_at, :timestamp
  
  # Method 2: Using primary_key method
  primary_key :user_id, :session_id
  
  # Method 3: Specifying partition and clustering keys
  primary_key [:user_id], [:session_id]
end
```

### Complex Primary Keys

```ruby
class TimeSeriesData < CassandraCpp::Model
  table_name 'sensor_data'
  
  # Composite partition key for data distribution
  column :sensor_id, :text
  column :date, :date
  
  # Clustering columns for ordering
  column :timestamp, :timestamp
  column :reading_id, :timeuuid
  
  # Data columns
  column :temperature, :float
  column :humidity, :float
  
  # Define the primary key structure
  primary_key [:sensor_id, :date], [:timestamp, :reading_id]
  
  # Define clustering order
  clustering_order timestamp: :desc, reading_id: :desc
end
```

## Validations

### Built-in Validations

```ruby
class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :email, :text
  column :name, :text
  column :age, :int
  column :username, :text
  column :website, :text
  column :bio, :text
  column :terms_accepted, :boolean
  
  # Presence validation
  validates :email, presence: true
  validates :name, presence: { message: "can't be blank" }
  
  # Uniqueness validation (requires secondary index or custom implementation)
  validates :email, uniqueness: true
  validates :username, uniqueness: { case_sensitive: false }
  
  # Format validation
  validates :email, format: { with: /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i }
  validates :website, format: { with: URI.regexp }, allow_blank: true
  
  # Length validation
  validates :username, length: { minimum: 3, maximum: 20 }
  validates :bio, length: { maximum: 500 }
  
  # Numericality validation
  validates :age, numericality: { greater_than_or_equal_to: 13, less_than: 150 }
  
  # Inclusion validation
  validates :status, inclusion: { in: %w[active inactive suspended] }
  
  # Acceptance validation
  validates :terms_accepted, acceptance: true
  
  # Custom validation method
  validate :email_not_from_spam_domain
  
  private
  
  def email_not_from_spam_domain
    spam_domains = ['tempmail.com', 'throwaway.email']
    domain = email.split('@').last
    if spam_domains.include?(domain)
      errors.add(:email, 'domain is not allowed')
    end
  end
end
```

### Conditional Validations

```ruby
class Product < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :category, :text
  column :price, :decimal
  column :discount_price, :decimal
  column :requires_shipping, :boolean
  column :weight, :float
  column :digital_download_url, :text
  
  # Conditional validation with if/unless
  validates :price, presence: true
  validates :discount_price, numericality: { less_than: :price }, if: :discount_price?
  
  # Using a Proc
  validates :weight, presence: true, if: -> { requires_shipping }
  validates :digital_download_url, presence: true, unless: :requires_shipping
  
  # Using a method
  validates :category, inclusion: { in: PREMIUM_CATEGORIES }, if: :premium?
  
  private
  
  def premium?
    price && price > 100
  end
end
```

### Custom Validators

```ruby
# Standalone validator class
class EmailValidator < CassandraCpp::Validator
  def validate(record)
    return if record.email.blank?
    
    unless record.email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
      record.errors.add(:email, 'is not a valid email address')
    end
    
    # Check DNS
    domain = record.email.split('@').last
    unless dns_exists?(domain)
      record.errors.add(:email, 'domain does not exist')
    end
  end
  
  private
  
  def dns_exists?(domain)
    # DNS lookup logic
    true
  end
end

class User < CassandraCpp::Model
  validates_with EmailValidator
end

# Inline custom validator
class CreditCard < CassandraCpp::Model
  column :number, :text
  column :cvv, :text
  column :expiry_date, :date
  
  validate do
    if number.present? && !valid_credit_card_number?(number)
      errors.add(:number, 'is not a valid credit card number')
    end
    
    if expiry_date.present? && expiry_date < Date.today
      errors.add(:expiry_date, 'has expired')
    end
  end
  
  private
  
  def valid_credit_card_number?(number)
    # Luhn algorithm implementation
    true
  end
end
```

## Associations

### Belongs To

```ruby
class Comment < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :post_id, :uuid
  column :user_id, :uuid
  column :content, :text
  column :created_at, :timestamp
  
  belongs_to :post
  belongs_to :user
  
  # With options
  belongs_to :author, class_name: 'User', foreign_key: :user_id
end

# Usage
comment = Comment.find(comment_id)
post = comment.post  # Executes: SELECT * FROM posts WHERE id = ?
user = comment.user
```

### Has Many

```ruby
class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :email, :text
  
  has_many :posts
  has_many :comments
  
  # With options
  has_many :published_posts, 
           class_name: 'Post', 
           foreign_key: :author_id,
           conditions: { status: 'published' }
  
  # Through association
  has_many :commented_posts, through: :comments, source: :post
end

# Usage
user = User.find(user_id)
posts = user.posts.all
recent_posts = user.posts.where(created_at: 1.week.ago..Time.now).limit(10)
```

### Has One

```ruby
class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  
  has_one :profile
  has_one :subscription, conditions: { active: true }
end

class Profile < CassandraCpp::Model
  column :user_id, :uuid, primary_key: true
  column :bio, :text
  column :avatar_url, :text
  
  belongs_to :user
end
```

### Many to Many

```ruby
# Using a join model
class Student < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  
  has_many :enrollments
  has_many :courses, through: :enrollments
end

class Course < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :title, :text
  
  has_many :enrollments
  has_many :students, through: :enrollments
end

class Enrollment < CassandraCpp::Model
  column :student_id, :uuid, partition_key: true
  column :course_id, :uuid, clustering_key: true
  column :enrolled_at, :timestamp
  column :grade, :text
  
  belongs_to :student
  belongs_to :course
end
```

### Polymorphic Associations

```ruby
class Comment < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :commentable_id, :uuid
  column :commentable_type, :text
  column :content, :text
  
  belongs_to :commentable, polymorphic: true
end

class Post < CassandraCpp::Model
  has_many :comments, as: :commentable
end

class Photo < CassandraCpp::Model
  has_many :comments, as: :commentable
end
```

## Callbacks

### Lifecycle Callbacks

```ruby
class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :email, :text
  column :name, :text
  column :email_normalized, :text
  column :activation_token, :text
  column :activated_at, :timestamp
  
  # Before callbacks
  before_validation :normalize_email
  before_save :generate_activation_token
  before_create :set_defaults
  before_update :track_changes
  before_destroy :cleanup_associations
  
  # After callbacks
  after_validation :log_validation_errors
  after_save :send_notifications
  after_create :send_welcome_email
  after_update :sync_external_services
  after_destroy :log_deletion
  
  # Around callbacks
  around_save :benchmark_save
  around_update :with_versioning
  
  private
  
  def normalize_email
    self.email_normalized = email.downcase.strip if email.present?
  end
  
  def generate_activation_token
    self.activation_token ||= SecureRandom.urlsafe_base64
  end
  
  def set_defaults
    self.created_at ||= Time.now
  end
  
  def track_changes
    if email_changed?
      # Log email change
      EmailChangeLog.create!(
        user_id: id,
        old_email: email_was,
        new_email: email,
        changed_at: Time.now
      )
    end
  end
  
  def benchmark_save
    start_time = Time.now
    yield  # Execute the save
    duration = Time.now - start_time
    Rails.logger.info "Save took #{duration}s"
  end
  
  def send_welcome_email
    UserMailer.welcome(self).deliver_later
  end
end
```

### Conditional Callbacks

```ruby
class Order < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :status, :text
  column :total, :decimal
  column :processed_at, :timestamp
  
  # Conditional callbacks
  before_save :calculate_tax, if: :taxable?
  after_save :send_receipt, if: -> { status == 'completed' }
  after_update :notify_shipping, if: :status_changed?, unless: :draft?
  
  # Multiple conditions
  before_destroy :can_be_destroyed?, if: [:draft?, :cancelled?]
  
  private
  
  def taxable?
    total > 0 && shipping_address.present?
  end
  
  def draft?
    status == 'draft'
  end
  
  def cancelled?
    status == 'cancelled'
  end
  
  def can_be_destroyed?
    throw(:abort) unless draft? || cancelled?
  end
end
```

### Callback Classes

```ruby
class AuditCallback
  def self.after_save(record)
    AuditLog.create!(
      model: record.class.name,
      record_id: record.id,
      action: record.new_record? ? 'create' : 'update',
      changes: record.changes,
      user_id: Current.user&.id,
      timestamp: Time.now
    )
  end
  
  def self.after_destroy(record)
    AuditLog.create!(
      model: record.class.name,
      record_id: record.id,
      action: 'destroy',
      user_id: Current.user&.id,
      timestamp: Time.now
    )
  end
end

class ImportantModel < CassandraCpp::Model
  after_save AuditCallback
  after_destroy AuditCallback
end
```

## Inheritance

### Single Table Inheritance (STI)

```ruby
# Note: Cassandra doesn't support traditional STI, but we can simulate it
class Vehicle < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :type, :text  # Discriminator column
  column :make, :text
  column :model, :text
  column :year, :int
  
  # Common methods
  def age
    Date.today.year - year
  end
end

class Car < Vehicle
  column :doors, :int
  column :trunk_capacity, :float
  
  def sedan?
    doors == 4
  end
end

class Motorcycle < Vehicle
  column :engine_type, :text
  column :has_sidecar, :boolean
  
  def cruiser?
    engine_type == 'v-twin'
  end
end

# Usage
car = Car.create!(
  make: 'Toyota',
  model: 'Camry',
  year: 2022,
  doors: 4
)

Vehicle.where(type: 'Car').each do |vehicle|
  car = vehicle.becomes(Car)  # Cast to specific type
  puts car.sedan?
end
```

### Abstract Base Classes

```ruby
class ApplicationModel < CassandraCpp::Model
  self.abstract_class = true
  
  # Common configuration
  column :created_at, :timestamp
  column :updated_at, :timestamp
  
  # Common callbacks
  before_create :set_timestamps
  before_update :update_timestamp
  
  # Common methods
  def touch
    self.updated_at = Time.now
    save
  end
  
  private
  
  def set_timestamps
    now = Time.now
    self.created_at ||= now
    self.updated_at ||= now
  end
  
  def update_timestamp
    self.updated_at = Time.now
  end
end

class User < ApplicationModel
  column :id, :uuid, primary_key: true
  column :email, :text
  # Inherits created_at, updated_at, and timestamp handling
end
```

### Module Inclusion

```ruby
module Timestampable
  extend ActiveSupport::Concern
  
  included do
    column :created_at, :timestamp
    column :updated_at, :timestamp
    
    before_create :set_created_at
    before_save :set_updated_at
  end
  
  def touch(column = :updated_at)
    update_column(column, Time.now)
  end
  
  private
  
  def set_created_at
    self.created_at ||= Time.now
  end
  
  def set_updated_at
    self.updated_at = Time.now
  end
end

module SoftDeletable
  extend ActiveSupport::Concern
  
  included do
    column :deleted_at, :timestamp
    
    default_scope { where(deleted_at: nil) }
    scope :deleted, -> { unscoped.where.not(deleted_at: nil) }
  end
  
  def destroy
    update(deleted_at: Time.now)
  end
  
  def really_destroy!
    super
  end
  
  def restore
    update(deleted_at: nil)
  end
  
  def deleted?
    deleted_at.present?
  end
end

class User < CassandraCpp::Model
  include Timestampable
  include SoftDeletable
  
  column :id, :uuid, primary_key: true
  column :email, :text
end
```

## Custom Type Handling

### Custom Type Converters

```ruby
# Define a custom type converter
class MoneyType < CassandraCpp::Type
  def self.type_name
    :money
  end
  
  def self.cassandra_type
    :decimal
  end
  
  def self.serialize(value)
    return nil if value.nil?
    
    case value
    when Money
      value.amount
    when Numeric
      BigDecimal(value.to_s)
    when String
      BigDecimal(value.gsub(/[$,]/, ''))
    else
      raise ArgumentError, "Cannot serialize #{value.class} to Money"
    end
  end
  
  def self.deserialize(value)
    return nil if value.nil?
    Money.new(value)
  end
end

# Register the type
CassandraCpp::Types.register(MoneyType)

# Use in a model
class Product < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :price, :money
  column :cost, :money
  
  def profit
    price - cost
  end
end
```

### JSON Serialization

```ruby
class JsonbType < CassandraCpp::Type
  def self.type_name
    :jsonb
  end
  
  def self.cassandra_type
    :text
  end
  
  def self.serialize(value)
    return nil if value.nil?
    
    case value
    when String
      value
    when Hash, Array
      JSON.generate(value)
    else
      JSON.generate(value.as_json)
    end
  end
  
  def self.deserialize(value)
    return nil if value.nil?
    JSON.parse(value, symbolize_names: true)
  rescue JSON::ParserError
    value
  end
end

class Event < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :metadata, :jsonb
  column :payload, :jsonb
  
  # Work with JSON data as Ruby objects
  def add_metadata(key, value)
    self.metadata ||= {}
    self.metadata[key] = value
  end
end
```

### Encrypted Attributes

```ruby
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
  
  def self.encrypt(value)
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.encrypt
    cipher.key = encryption_key
    iv = cipher.random_iv
    cipher.auth_data = ''
    
    encrypted = cipher.update(value) + cipher.final
    tag = cipher.auth_tag
    
    [iv, tag, encrypted].map { |part| Base64.strict_encode64(part) }.join('|')
  end
  
  def self.decrypt(value)
    iv, tag, encrypted = value.split('|').map { |part| Base64.strict_decode64(part) }
    
    cipher = OpenSSL::Cipher.new('AES-256-GCM')
    cipher.decrypt
    cipher.key = encryption_key
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.auth_data = ''
    
    cipher.update(encrypted) + cipher.final
  end
  
  def self.encryption_key
    ENV.fetch('ENCRYPTION_KEY')
  end
end

class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :email, :text
  column :ssn, :encrypted
  column :credit_card, :encrypted
end
```

## Model Configuration

### Table Options

```ruby
class OptimizedTable < CassandraCpp::Model
  table_name 'optimized_data'
  
  # Table properties
  table_properties(
    compression: {
      'sstable_compression' => 'LZ4Compressor',
      'chunk_length_kb' => 64
    },
    compaction: {
      'class' => 'SizeTieredCompactionStrategy',
      'min_threshold' => 4,
      'max_threshold' => 32
    },
    caching: {
      'keys' => 'ALL',
      'rows_per_partition' => 100
    },
    gc_grace_seconds: 864000,
    bloom_filter_fp_chance: 0.01,
    read_repair_chance: 0.1,
    dclocal_read_repair_chance: 0.1,
    memtable_flush_period_in_ms: 3600000
  )
  
  # TTL configuration
  default_ttl 86400  # 24 hours
  
  # Specify consistency levels
  consistency_level :quorum
  serial_consistency_level :serial
end
```

### Secondary Indexes

```ruby
class User < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :email, :text, index: true
  column :username, :text, index: { name: 'users_username_idx' }
  column :created_at, :timestamp
  column :country, :text
  column :status, :text
  
  # Create composite index
  index [:country, :status], name: 'users_country_status_idx'
  
  # Create indexes manually
  def self.create_indexes!
    execute("CREATE INDEX IF NOT EXISTS users_email_idx ON #{table_name} (email)")
    execute("CREATE INDEX IF NOT EXISTS users_created_at_idx ON #{table_name} (created_at)")
  end
end
```

### Materialized Views

```ruby
class UserByEmail < CassandraCpp::Model
  # Define as materialized view
  materialized_view_of User
  
  # Primary key must include all columns from base table PK
  primary_key :email, :id
  
  # Select specific columns
  select_columns :id, :email, :name, :created_at
  
  # Where clause (required for MV)
  where_clause 'email IS NOT NULL'
end

# Create the materialized view
UserByEmail.create_materialized_view!

# Query the view
user = UserByEmail.find_by(email: 'john@example.com')
```

## Advanced Features

### Batch Loading

```ruby
class BatchLoader < CassandraCpp::Model
  # Enable batch loading to avoid N+1 queries
  def self.batch_load(ids, options = {})
    return [] if ids.empty?
    
    # Build IN query
    placeholders = (['?'] * ids.size).join(', ')
    query = "SELECT * FROM #{table_name} WHERE id IN (#{placeholders})"
    
    # Execute query
    results = execute(query, *ids)
    
    # Build hash for quick lookup
    results_hash = results.index_by { |row| row['id'] }
    
    # Return in same order as input
    ids.map { |id| results_hash[id] }.compact
  end
  
  # Batch association loading
  has_many :comments do
    def load_in_batches(batch_size: 1000)
      comment_ids = owner.comment_ids
      
      comment_ids.each_slice(batch_size).flat_map do |batch_ids|
        Comment.batch_load(batch_ids)
      end
    end
  end
end
```

### Query Caching

```ruby
class CachedModel < CassandraCpp::Model
  # Enable query caching
  def self.cache_queries(expires_in: 5.minutes)
    @query_cache_expires_in = expires_in
  end
  
  def self.find_cached(id)
    cache_key = "#{table_name}:#{id}"
    
    Rails.cache.fetch(cache_key, expires_in: @query_cache_expires_in) do
      find(id)
    end
  end
  
  # Invalidate cache on updates
  after_save :invalidate_cache
  after_destroy :invalidate_cache
  
  private
  
  def invalidate_cache
    Rails.cache.delete("#{self.class.table_name}:#{id}")
  end
end
```

### Dirty Tracking

```ruby
class TrackedModel < CassandraCpp::Model
  include CassandraCpp::DirtyTracking
  
  column :id, :uuid, primary_key: true
  column :name, :text
  column :email, :text
  column :status, :text
  
  # Track specific attributes
  track_attributes :name, :email, :status
end

# Usage
user = TrackedModel.find(id)
user.name = 'New Name'

user.changed?        # => true
user.name_changed?   # => true
user.name_was        # => 'Old Name'
user.changes         # => { name: ['Old Name', 'New Name'] }

user.save
user.previous_changes # => { name: ['Old Name', 'New Name'] }
```

### Optimistic Locking

```ruby
class VersionedModel < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :name, :text
  column :version, :bigint, default: 0
  
  # Enable optimistic locking
  optimistic_locking column: :version
  
  # Override save to handle conflicts
  def save
    if persisted?
      # Use lightweight transaction for atomic check-and-set
      result = self.class.execute(
        "UPDATE #{self.class.table_name} 
         SET name = ?, version = ? 
         WHERE id = ? 
         IF version = ?",
        name,
        version + 1,
        id,
        version
      )
      
      if result.first['[applied]']
        self.version += 1
        true
      else
        raise CassandraCpp::StaleObjectError, 
              "Attempted to update stale object"
      end
    else
      super
    end
  end
end
```

## Best Practices

### 1. Design for Cassandra

```ruby
# Good: Denormalized model optimized for queries
class UserActivity < CassandraCpp::Model
  # Partition by user for efficient user queries
  column :user_id, :uuid, partition_key: true
  column :activity_timestamp, :timestamp, clustering_key: true
  column :activity_id, :timeuuid, clustering_key: true
  
  # Denormalized user data to avoid joins
  column :user_name, :text
  column :user_email, :text
  
  # Activity data
  column :activity_type, :text
  column :activity_details, :text
  
  # Clustering order for recent activities first
  clustering_order activity_timestamp: :desc
end

# Bad: Normalized design requiring joins
class Activity < CassandraCpp::Model
  column :id, :uuid, primary_key: true
  column :user_id, :uuid  # Would require join to get user info
  column :type, :text
  column :details, :text
end
```

### 2. Use Prepared Statements

```ruby
class User < CassandraCpp::Model
  # Cache prepared statements at class level
  class << self
    def find_by_email_statement
      @find_by_email_stmt ||= prepare(
        "SELECT * FROM #{table_name} WHERE email = ? ALLOW FILTERING"
      )
    end
    
    def update_last_login_statement
      @update_last_login_stmt ||= prepare(
        "UPDATE #{table_name} SET last_login = ? WHERE id = ?"
      )
    end
  end
  
  def self.find_by_email(email)
    result = execute(find_by_email_statement.bind(email))
    result.first
  end
  
  def update_last_login!
    self.class.execute(
      self.class.update_last_login_statement.bind(Time.now, id)
    )
  end
end
```

### 3. Batch Operations Wisely

```ruby
class EventLog < CassandraCpp::Model
  # Good: Batch operations to same partition
  def self.log_user_events(user_id, events)
    batch do
      events.each do |event|
        create!(
          user_id: user_id,  # Same partition
          event_id: CassandraCpp::Uuid.generate,
          timestamp: Time.now,
          type: event[:type],
          data: event[:data]
        )
      end
    end
  end
  
  # Bad: Batch operations across partitions
  def self.log_events_poorly(events)
    batch do
      events.each do |event|
        create!(
          user_id: event[:user_id],  # Different partitions!
          event_id: CassandraCpp::Uuid.generate,
          timestamp: Time.now,
          type: event[:type]
        )
      end
    end
  end
end
```

## Next Steps

- [Queries](05_queries.md) - Advanced querying with the ORM
- [Migrations](06_migrations.md) - Managing schema changes
- [Performance](07_performance.md) - Optimizing model performance
- [Advanced Features](08_advanced_features.md) - Async operations and more