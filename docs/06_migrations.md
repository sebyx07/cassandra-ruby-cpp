# Migrations Guide

Cassandra-CPP provides a migration system to manage schema changes over time. This guide covers creating, running, and managing migrations for your Cassandra schema evolution.

## Table of Contents

- [Migration Basics](#migration-basics)
- [Creating Migrations](#creating-migrations)
- [Migration Structure](#migration-structure)
- [Running Migrations](#running-migrations)
- [Rollback Strategies](#rollback-strategies)
- [Schema Changes](#schema-changes)
- [Data Migrations](#data-migrations)
- [Version Management](#version-management)
- [Best Practices](#best-practices)
- [Advanced Scenarios](#advanced-scenarios)

## Migration Basics

### What are Migrations?

Migrations are versioned schema changes that allow you to evolve your database structure over time. They provide:

- **Version Control**: Track schema changes with your application code
- **Collaboration**: Team members can synchronize schema changes
- **Deployment**: Automated schema updates during deployment
- **Rollback**: Ability to revert changes when needed

### Migration Files

```ruby
# db/migrate/001_create_users.rb
class CreateUsers < CassandraCpp::Migration
  def up
    create_table :users do |t|
      t.uuid :id, primary_key: true
      t.text :email
      t.text :name
      t.int :age
      t.timestamp :created_at
      t.timestamp :updated_at
      
      t.index :email
    end
  end
  
  def down
    drop_table :users
  end
end
```

## Creating Migrations

### Generator Command

```bash
# Create a new migration
bundle exec cassandra_cpp generate migration CreateUsers

# Create migration with table operations
bundle exec cassandra_cpp generate migration CreateUsers \
  id:uuid:primary_key \
  email:text:index \
  name:text \
  age:int

# Create migration for model changes
bundle exec cassandra_cpp generate migration AddIndexToUsersEmail \
  --table=users \
  --add-index=email

# Create data migration
bundle exec cassandra_cpp generate migration MigrateUserData \
  --data-migration
```

### Manual Migration Creation

```ruby
# Create file: db/migrate/002_add_status_to_users.rb
class AddStatusToUsers < CassandraCpp::Migration
  def up
    add_column :users, :status, :text, default: 'active'
    add_index :users, :status, name: 'users_status_idx'
  end
  
  def down
    remove_index :users, :status
    remove_column :users, :status
  end
end
```

## Migration Structure

### Basic Migration Template

```ruby
class MigrationName < CassandraCpp::Migration
  # Schema version (auto-generated)
  version '20231201120000'
  
  # Migration description
  description 'Add user status tracking'
  
  # Dependencies (optional)
  depends_on '20231201110000'
  
  # Apply changes
  def up
    # Schema changes go here
  end
  
  # Revert changes
  def down
    # Rollback logic goes here
  end
  
  # Data transformation (optional)
  def migrate_data
    # Data migration logic
  end
  
  # Validation after migration
  def validate
    # Ensure migration succeeded
  end
end
```

### Migration Methods

```ruby
class ComprehensiveMigration < CassandraCpp::Migration
  def up
    # Create tables
    create_table :products do |t|
      t.uuid :id, primary_key: true
      t.text :name
      t.decimal :price
      t.text :category
      t.set :tags, of: :text
      t.map :attributes, of: [:text, :text]
      
      t.index :category
      t.index :tags
    end
    
    # Modify existing tables
    change_table :users do |t|
      t.add_column :last_login, :timestamp
      t.add_column :preferences, :map, of: [:text, :text]
      t.change_column :age, :smallint  # Type change
      t.rename_column :full_name, :name
      t.remove_column :deprecated_field
    end
    
    # Create indexes
    add_index :users, [:country, :status], name: 'country_status_idx'
    add_index :products, :price, name: 'products_price_idx'
    
    # Create materialized views
    create_materialized_view :users_by_email do |mv|
      mv.select_from :users
      mv.primary_key :email, :id
      mv.where 'email IS NOT NULL'
    end
    
    # Create user-defined types
    create_type :address do |t|
      t.text :street
      t.text :city
      t.text :state
      t.text :zip_code
    end
  end
  
  def down
    drop_materialized_view :users_by_email
    drop_type :address
    remove_index :users, [:country, :status]
    remove_index :products, :price
    drop_table :products
    
    change_table :users do |t|
      t.remove_column :last_login
      t.remove_column :preferences
      t.change_column :age, :int
      t.rename_column :name, :full_name
      t.add_column :deprecated_field, :text
    end
  end
end
```

## Running Migrations

### Command Line Interface

```bash
# Run all pending migrations
bundle exec cassandra_cpp db:migrate

# Run migrations up to specific version
bundle exec cassandra_cpp db:migrate VERSION=20231201120000

# Check migration status
bundle exec cassandra_cpp db:migrate:status

# Show current schema version
bundle exec cassandra_cpp db:version

# Show migration details
bundle exec cassandra_cpp db:migrate:info
```

### Programmatic Execution

```ruby
# Run migrations programmatically
migrator = CassandraCpp::Migrator.new

# Run all pending migrations
migrator.migrate

# Run to specific version
migrator.migrate_to('20231201120000')

# Check if migrations are needed
if migrator.pending_migrations?
  puts "#{migrator.pending_count} migrations pending"
  migrator.migrate
end

# Get migration status
status = migrator.status
status.each do |migration|
  puts "#{migration.version} #{migration.status} #{migration.name}"
end
```

### Environment-Specific Migrations

```ruby
# config/environments/production.rb
CassandraCpp::Migrator.configure do |config|
  # Require explicit confirmation in production
  config.require_confirmation = true
  
  # Set migration timeout
  config.migration_timeout = 300  # 5 minutes
  
  # Backup before migration
  config.backup_before_migrate = true
  
  # Parallel migration execution
  config.parallel_migrations = false  # Safer in production
end

# Run with confirmation
bundle exec cassandra_cpp db:migrate --confirm
```

## Rollback Strategies

### Simple Rollback

```bash
# Rollback last migration
bundle exec cassandra_cpp db:rollback

# Rollback multiple steps
bundle exec cassandra_cpp db:rollback STEP=3

# Rollback to specific version
bundle exec cassandra_cpp db:rollback VERSION=20231201110000
```

### Safe Rollback Patterns

```ruby
class SafeColumnAddition < CassandraCpp::Migration
  def up
    # Add column with default value
    add_column :users, :status, :text, default: 'active'
    
    # Populate existing records
    execute <<-CQL
      UPDATE users SET status = 'active' WHERE status IS NULL
    CQL
  end
  
  def down
    # Safe to remove - column was added by this migration
    remove_column :users, :status
  end
  
  # Validation ensures migration completed successfully
  def validate
    result = execute("SELECT count(*) FROM users WHERE status IS NULL")
    null_count = result.first['count']
    
    if null_count > 0
      raise "Migration incomplete: #{null_count} users have NULL status"
    end
  end
end
```

### Irreversible Migrations

```ruby
class IrreversibleDataCleanup < CassandraCpp::Migration
  def up
    # Delete old data
    execute "DELETE FROM audit_logs WHERE created_at < '2022-01-01'"
    
    # Mark as irreversible
    mark_irreversible
  end
  
  def down
    # This will raise an error
    raise CassandraCpp::IrreversibleMigration, 
          "Cannot restore deleted audit logs"
  end
end
```

## Schema Changes

### Table Operations

```ruby
class TableOperations < CassandraCpp::Migration
  def up
    # Create table with all options
    create_table :analytics_events do |t|
      # Composite partition key
      t.text :app_id, partition_key: true
      t.date :event_date, partition_key: true
      
      # Clustering columns
      t.timestamp :event_time, clustering_key: true
      t.uuid :event_id, clustering_key: true
      
      # Data columns
      t.text :event_type
      t.text :user_id
      t.map :properties, of: [:text, :text]
      
      # Table options
      t.clustering_order event_time: :desc, event_id: :asc
      t.compression 'LZ4Compressor'
      t.gc_grace_seconds 86400
      t.bloom_filter_fp_chance 0.01
    end
    
    # Rename table
    rename_table :old_events, :legacy_events
    
    # Copy data between tables
    copy_table_data :legacy_events, :analytics_events do |row|
      # Transform data during copy
      {
        app_id: row['application_id'],
        event_date: row['created_at'].to_date,
        event_time: row['created_at'],
        event_id: CassandraCpp::Uuid.generate,
        event_type: row['type'],
        user_id: row['user_uuid'],
        properties: JSON.parse(row['metadata'] || '{}')
      }
    end
  end
end
```

### Column Operations

```ruby
class ColumnOperations < CassandraCpp::Migration
  def up
    # Add columns
    add_column :users, :phone, :text
    add_column :users, :preferences, :map, of: [:text, :text], default: {}
    add_column :users, :tags, :set, of: :text, default: Set.new
    
    # Change column types (limited in Cassandra)
    change_column :users, :age, :smallint  # Only compatible changes
    
    # Rename columns
    rename_column :users, :full_name, :display_name
    
    # Remove columns
    remove_column :users, :deprecated_field
    remove_column :users, :old_status  # This drops data!
  end
  
  def down
    add_column :users, :deprecated_field, :text
    add_column :users, :old_status, :text
    rename_column :users, :display_name, :full_name
    change_column :users, :age, :int
    remove_column :users, :tags
    remove_column :users, :preferences
    remove_column :users, :phone
  end
end
```

### Index Management

```ruby
class IndexManagement < CassandraCpp::Migration
  def up
    # Simple indexes
    add_index :users, :email, name: 'users_email_idx'
    add_index :products, :category
    
    # Composite indexes
    add_index :orders, [:customer_id, :status], name: 'orders_customer_status'
    
    # Collection indexes
    add_index :products, :tags, name: 'products_tags_idx'  # For SET<text>
    add_index :events, 'keys(properties)', name: 'events_property_keys'  # Map keys
    
    # Custom index with options
    execute <<-CQL
      CREATE CUSTOM INDEX products_search_idx ON products (description)
      USING 'org.apache.cassandra.index.sasi.SASIIndex'
      WITH OPTIONS = {
        'mode': 'CONTAINS',
        'analyzer_class': 'org.apache.cassandra.index.sasi.analyzer.StandardAnalyzer',
        'case_sensitive': 'false'
      }
    CQL
  end
  
  def down
    remove_index :products, 'products_search_idx'
    remove_index :events, 'events_property_keys'
    remove_index :products, :tags
    remove_index :orders, [:customer_id, :status]
    remove_index :products, :category
    remove_index :users, :email
  end
end
```

### User-Defined Types

```ruby
class UserDefinedTypes < CassandraCpp::Migration
  def up
    # Create UDT
    create_type :contact_info do |t|
      t.text :email
      t.text :phone
      t.text :website
    end
    
    # Create nested UDT
    create_type :address do |t|
      t.text :street
      t.text :city
      t.text :state
      t.text :zip_code
      t.text :country
    end
    
    create_type :location do |t|
      t.frozen :address, of: :address
      t.double :latitude
      t.double :longitude
    end
    
    # Use UDT in table
    create_table :businesses do |t|
      t.uuid :id, primary_key: true
      t.text :name
      t.frozen :contact, of: :contact_info
      t.frozen :location, of: :location
    end
  end
  
  def down
    drop_table :businesses
    drop_type :location
    drop_type :address
    drop_type :contact_info
  end
end
```

## Data Migrations

### Simple Data Transformation

```ruby
class UpdateUserStatuses < CassandraCpp::Migration
  def up
    # Add status column
    add_column :users, :status, :text
    
    # Migrate data
    migrate_data
  end
  
  def migrate_data
    # Process in batches to avoid timeouts
    batch_size = 1000
    last_id = nil
    
    loop do
      # Get batch of users
      query = "SELECT id, last_login FROM users LIMIT #{batch_size}"
      query += " WHERE token(id) > token(?)" if last_id
      
      result = execute(query, *(last_id ? [last_id] : []))
      users = result.to_a
      
      break if users.empty?
      
      # Update each user's status
      users.each do |user|
        status = determine_status(user['last_login'])
        execute(
          "UPDATE users SET status = ? WHERE id = ?",
          status, user['id']
        )
      end
      
      last_id = users.last['id']
      
      # Progress indicator
      puts "Processed batch ending with ID: #{last_id}"
    end
  end
  
  private
  
  def determine_status(last_login)
    return 'inactive' if last_login.nil?
    
    days_since_login = (Time.now - last_login) / 86400
    
    case days_since_login
    when 0..7 then 'active'
    when 8..30 then 'idle'
    else 'inactive'
    end
  end
end
```

### Complex Data Migration

```ruby
class NormalizeUserData < CassandraCpp::Migration
  def up
    # Create new normalized tables
    create_table :user_profiles do |t|
      t.uuid :user_id, primary_key: true
      t.text :first_name
      t.text :last_name
      t.text :bio
      t.text :avatar_url
    end
    
    create_table :user_settings do |t|
      t.uuid :user_id, primary_key: true
      t.boolean :email_notifications, default: true
      t.boolean :sms_notifications, default: false
      t.text :timezone, default: 'UTC'
      t.text :language, default: 'en'
    end
    
    # Migrate data from denormalized users table
    migrate_data
  end
  
  def migrate_data
    # Create prepared statements for efficiency
    profile_stmt = prepare(<<-CQL)
      INSERT INTO user_profiles (user_id, first_name, last_name, bio, avatar_url)
      VALUES (?, ?, ?, ?, ?)
    CQL
    
    settings_stmt = prepare(<<-CQL)
      INSERT INTO user_settings (user_id, email_notifications, sms_notifications, timezone, language)
      VALUES (?, ?, ?, ?, ?)
    CQL
    
    # Process users in batches
    process_in_batches('SELECT * FROM users', 500) do |users|
      # Use batch for atomic writes
      batch do
        users.each do |user|
          # Extract name parts
          name_parts = (user['name'] || '').split(' ', 2)
          first_name = name_parts[0] || ''
          last_name = name_parts[1] || ''
          
          # Create profile
          execute(profile_stmt.bind(
            user['id'],
            first_name,
            last_name,
            user['bio'],
            user['avatar_url']
          ))
          
          # Create settings with defaults
          execute(settings_stmt.bind(
            user['id'],
            user['email_notifications'] != false,  # Default true
            user['sms_notifications'] == true,     # Default false
            user['timezone'] || 'UTC',
            user['language'] || 'en'
          ))
        end
      end
    end
  end
  
  def validate
    # Ensure all users have profiles and settings
    user_count = execute("SELECT count(*) FROM users").first['count']
    profile_count = execute("SELECT count(*) FROM user_profiles").first['count']
    settings_count = execute("SELECT count(*) FROM user_settings").first['count']
    
    unless user_count == profile_count && user_count == settings_count
      raise "Data migration incomplete: users=#{user_count}, profiles=#{profile_count}, settings=#{settings_count}"
    end
  end
  
  private
  
  def process_in_batches(query, batch_size)
    last_token = nil
    
    loop do
      batch_query = "#{query} LIMIT #{batch_size}"
      batch_query += " WHERE token(id) > ?" if last_token
      
      result = execute(batch_query, *(last_token ? [last_token] : []))
      batch = result.to_a
      
      break if batch.empty?
      
      yield batch
      
      last_token = batch.last['id']
      puts "Processed batch ending with ID: #{last_token}"
    end
  end
end
```

## Version Management

### Migration Tracking

```ruby
# Migration state is tracked in system table
class MigrationTracker
  def self.applied_migrations
    execute(<<-CQL)
      SELECT version, name, applied_at FROM cassandra_cpp_migrations
      ORDER BY version ASC
    CQL
  end
  
  def self.pending_migrations
    applied_versions = applied_migrations.map { |m| m['version'] }
    
    all_migrations.reject do |migration|
      applied_versions.include?(migration.version)
    end
  end
  
  def self.record_migration(migration)
    execute(<<-CQL, migration.version, migration.name, Time.now)
      INSERT INTO cassandra_cpp_migrations (version, name, applied_at)
      VALUES (?, ?, ?)
    CQL
  end
end
```

### Schema Versioning

```ruby
# Check current schema version
current_version = CassandraCpp::Migrator.current_version
puts "Current schema version: #{current_version}"

# Get all version information
version_info = CassandraCpp::Migrator.version_info
version_info.each do |info|
  puts "#{info.version}: #{info.status} - #{info.description}"
end

# Check if schema is up to date
if CassandraCpp::Migrator.pending_migrations?
  puts "Schema updates needed"
else
  puts "Schema is up to date"
end
```

### Branch Migrations

```ruby
# Handle migrations from different branches
class BranchMigrationResolver
  def self.resolve_conflicts
    migrations = CassandraCpp::Migrator.all_migrations
    conflicts = find_version_conflicts(migrations)
    
    conflicts.each do |conflict|
      puts "Version conflict: #{conflict[:version]}"
      puts "  Migration A: #{conflict[:migration_a].name}"
      puts "  Migration B: #{conflict[:migration_b].name}"
      
      # Resolve by renaming one migration
      resolve_conflict(conflict)
    end
  end
  
  private
  
  def self.find_version_conflicts(migrations)
    # Find migrations with same version but different content
    grouped = migrations.group_by(&:version)
    grouped.select { |_, group| group.size > 1 }
  end
  
  def self.resolve_conflict(conflict)
    # Automatically resolve by incrementing version
    newer_migration = conflict[:migration_b]
    new_version = generate_new_version
    
    File.rename(newer_migration.filename, 
                newer_migration.filename.gsub(conflict[:version], new_version))
    
    puts "Resolved: Renamed to version #{new_version}"
  end
end
```

## Best Practices

### 1. Always Write Down Migration

```ruby
class GoodMigration < CassandraCpp::Migration
  def up
    add_column :users, :status, :text, default: 'active'
  end
  
  # Always implement down method
  def down
    remove_column :users, :status
  end
end
```

### 2. Test Migrations Thoroughly

```ruby
# Create test for migration
class TestCreateUsers < MiniTest::Test
  def setup
    @migrator = CassandraCpp::Migrator.new(test_session)
  end
  
  def test_migration_creates_table
    @migrator.run_migration(CreateUsers)
    
    # Verify table exists
    result = test_session.execute(<<-CQL)
      SELECT table_name FROM system_schema.tables 
      WHERE keyspace_name = '#{test_keyspace}' 
      AND table_name = 'users'
    CQL
    
    assert_equal 1, result.size
  end
  
  def test_migration_rollback
    @migrator.run_migration(CreateUsers)
    @migrator.rollback_migration(CreateUsers)
    
    # Verify table doesn't exist
    result = test_session.execute(<<-CQL)
      SELECT table_name FROM system_schema.tables 
      WHERE keyspace_name = '#{test_keyspace}' 
      AND table_name = 'users'
    CQL
    
    assert_equal 0, result.size
  end
end
```

### 3. Use Transactions for Data Integrity

```ruby
class SafeDataMigration < CassandraCpp::Migration
  def migrate_data
    # Use lightweight transactions for data integrity
    users = execute("SELECT id, email FROM users WHERE migrated IS NULL")
    
    users.each do |user|
      # Atomic check-and-set to prevent double processing
      result = execute(<<-CQL, user['id'])
        UPDATE users SET migrated = true WHERE id = ? IF migrated IS NULL
      CQL
      
      if result.first['[applied]']
        # Safely process this user
        process_user(user)
      end
    end
  end
end
```

### 4. Handle Large Data Sets

```ruby
class EfficientDataMigration < CassandraCpp::Migration
  def migrate_data
    # Process data in parallel when possible
    total_processed = 0
    threads = []
    
    # Create worker threads
    4.times do |i|
      threads << Thread.new do
        process_partition(i, 4)
      end
    end
    
    # Wait for completion
    threads.each(&:join)
  end
  
  private
  
  def process_partition(partition, total_partitions)
    # Process subset of data based on token range
    # This allows parallel processing
  end
end
```

## Advanced Scenarios

### Multi-Keyspace Migrations

```ruby
class MultiKeyspaceMigration < CassandraCpp::Migration
  def up
    # Migrate multiple keyspaces
    keyspaces = ['app_data', 'analytics', 'user_sessions']
    
    keyspaces.each do |keyspace|
      with_keyspace(keyspace) do
        add_column :events, :processed_at, :timestamp
        add_index :events, :processed_at
      end
    end
  end
  
  private
  
  def with_keyspace(keyspace)
    original_keyspace = current_keyspace
    use_keyspace(keyspace)
    yield
  ensure
    use_keyspace(original_keyspace)
  end
end
```

### Schema Evolution Strategies

```ruby
class SchemaEvolution < CassandraCpp::Migration
  # Strategy 1: Additive changes only
  def up_additive
    # Add new columns with defaults
    add_column :users, :v2_data, :text
    add_column :users, :schema_version, :int, default: 1
    
    # Create parallel table for new structure
    create_table :users_v2 do |t|
      # New optimized structure
    end
  end
  
  # Strategy 2: Blue-green migration
  def up_blue_green
    # Create new "green" table
    create_table :users_green do |t|
      # New structure
    end
    
    # Migrate data to green table
    migrate_to_green_table
    
    # Application will gradually switch to green table
    # Old blue table can be dropped in future migration
  end
  
  # Strategy 3: Shadow table migration
  def up_shadow
    # Create shadow table with new structure
    create_table :users_shadow, like: :users
    add_column :users_shadow, :new_field, :text
    
    # Set up triggers to keep shadow in sync
    # (Note: Cassandra doesn't have triggers, use application logic)
    
    # Eventually rename shadow to main table
  end
end
```

### Handling Migration Failures

```ruby
class RobustMigration < CassandraCpp::Migration
  def up
    begin
      # Checkpoint system for resumable migrations
      checkpoint = load_checkpoint
      
      unless checkpoint.completed?(:create_table)
        create_table :new_structure
        save_checkpoint(:create_table)
      end
      
      unless checkpoint.completed?(:migrate_data)
        migrate_data_with_resume(checkpoint)
        save_checkpoint(:migrate_data)
      end
      
      unless checkpoint.completed?(:validate)
        validate_migration
        save_checkpoint(:validate)
      end
      
      # Clean up checkpoint
      clear_checkpoint
      
    rescue => error
      # Log error and preserve checkpoint for resume
      log_migration_error(error)
      raise
    end
  end
  
  private
  
  def migrate_data_with_resume(checkpoint)
    last_processed = checkpoint.last_processed_id
    
    # Resume from where we left off
    process_remaining_data(from: last_processed) do |batch|
      checkpoint.update_progress(batch.last.id)
    end
  end
end
```

## Next Steps

- [Performance](07_performance.md) - Optimize your schema and queries
- [Advanced Features](08_advanced_features.md) - Async operations and advanced patterns
- [Troubleshooting](09_troubleshooting.md) - Debug migration issues