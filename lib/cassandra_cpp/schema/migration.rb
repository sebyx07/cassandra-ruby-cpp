# frozen_string_literal: true

require_relative 'string_extensions'

module CassandraCpp
  module Schema
    # Base class for database migrations
    # 
    # Migrations provide a way to alter your database schema over time
    # in a consistent and organized fashion.
    #
    # @example Creating a migration
    #   class CreateUsersTable < CassandraCpp::Schema::Migration
    #     def up
    #       create_table :users do |t|
    #         t.uuid :id, primary_key: true
    #         t.text :name, null: false
    #         t.text :email
    #         t.timestamp :created_at, default: 'now()'
    #       end
    #       
    #       create_index :users, :email
    #     end
    #     
    #     def down
    #       drop_table :users
    #     end
    #   end
    class Migration
      # @param session [CassandraCpp::Session] Active Cassandra session
      def initialize(session)
        @session = session
        @schema = Manager.new(session, session.keyspace)
      end

      # Override this method to define forward migration
      def up
        raise NotImplementedError, "Subclass must implement the 'up' method"
      end

      # Override this method to define rollback migration
      def down
        raise NotImplementedError, "Subclass must implement the 'down' method"
      end

      # Run the migration forward
      def migrate!
        up
      end

      # Rollback the migration
      def rollback!
        down
      end

      # Get migration version from class name
      # @return [String] Migration version
      def version
        self.class.name.match(/(\d+)_/)[1] if self.class.name.match(/(\d+)_/)
      end

      # Get migration name from class name
      # @return [String] Migration name
      def name
        self.class.name.underscore.gsub(/^.*\//, '')
      end

      protected

      # Create a new table
      # @param table_name [String, Symbol] Name of the table
      # @param block [Proc] Block defining table structure
      def create_table(table_name, &block)
        @schema.create_table(table_name.to_s, &block)
      end

      # Drop a table
      # @param table_name [String, Symbol] Name of the table
      # @param if_exists [Boolean] Add IF EXISTS clause
      def drop_table(table_name, if_exists: true)
        @schema.drop_table(table_name.to_s, if_exists: if_exists)
      end

      # Add a column to a table
      # @param table_name [String, Symbol] Name of the table
      # @param column_name [String, Symbol] Name of the column
      # @param column_type [Symbol] Type of the column
      def add_column(table_name, column_name, column_type)
        @schema.add_column(table_name.to_s, column_name.to_s, column_type)
      end

      # Drop a column from a table
      # @param table_name [String, Symbol] Name of the table
      # @param column_name [String, Symbol] Name of the column
      def drop_column(table_name, column_name)
        @schema.drop_column(table_name.to_s, column_name.to_s)
      end

      # Create an index
      # @param table_name [String, Symbol] Name of the table
      # @param column_name [String, Symbol] Name of the column
      # @param index_name [String, Symbol, nil] Custom index name
      def create_index(table_name, column_name, index_name: nil)
        @schema.create_index(
          table_name.to_s, 
          column_name.to_s, 
          index_name: index_name&.to_s
        )
      end

      # Drop an index
      # @param index_name [String, Symbol] Name of the index
      def drop_index(index_name)
        @schema.drop_index(index_name.to_s)
      end

      # Execute raw CQL
      # @param cql [String] CQL statement to execute
      def execute(cql)
        @session.execute(cql)
      end

      # Execute CQL with parameters
      # @param cql [String] CQL statement to execute
      # @param params [Array] Parameters for the statement
      def execute_with_params(cql, params)
        @session.execute(cql, *params)
      end

      # Check if table exists
      # @param table_name [String, Symbol] Name of the table
      # @return [Boolean] true if table exists
      def table_exists?(table_name)
        @schema.table_exists?(table_name.to_s)
      end

      # Get table columns
      # @param table_name [String, Symbol] Name of the table
      # @return [Array<Hash>] Array of column definitions
      def columns(table_name)
        @schema.columns(table_name.to_s)
      end
    end

    # Migration runner for executing migrations
    class MigrationRunner
      # @param session [CassandraCpp::Session] Active Cassandra session
      def initialize(session)
        @session = session
        @schema = Manager.new(session, session.keyspace)
        ensure_schema_migrations_table!
      end

      # Run all pending migrations
      # @param migration_files [Array<String>] Array of migration file paths
      def migrate!(migration_files = [])
        migration_files = find_migration_files if migration_files.empty?
        applied_versions = get_applied_versions
        
        migration_files.sort.each do |file|
          version = extract_version_from_filename(file)
          next if applied_versions.include?(version)
          
          run_migration_file(file, :up)
          record_migration(version, File.basename(file, '.rb'))
        end
      end

      # Rollback migrations
      # @param steps [Integer] Number of migrations to rollback
      def rollback!(steps = 1)
        applied_migrations = get_applied_migrations.sort_by { |m| m['version'] }.reverse
        
        applied_migrations.first(steps).each do |migration_record|
          file_pattern = "#{migration_record['version']}_*.rb"
          migration_files = Dir.glob(File.join(migrations_path, file_pattern))
          
          if migration_files.any?
            run_migration_file(migration_files.first, :down)
            remove_migration_record(migration_record['version'])
          end
        end
      end

      # Get migration status
      # @return [Array<Hash>] Array of migration status information
      def status
        migration_files = find_migration_files
        applied_versions = get_applied_versions
        
        migration_files.sort.map do |file|
          version = extract_version_from_filename(file)
          {
            version: version,
            name: File.basename(file, '.rb'),
            status: applied_versions.include?(version) ? 'applied' : 'pending'
          }
        end
      end

      private

      # Ensure the schema_migrations table exists
      def ensure_schema_migrations_table!
        return if @schema.table_exists?('schema_migrations')
        
        @session.execute(<<~CQL)
          CREATE TABLE schema_migrations (
            version text PRIMARY KEY,
            name text,
            applied_at timestamp
          )
        CQL
      end

      # Get list of applied migration versions
      # @return [Array<String>] Array of applied versions
      def get_applied_versions
        result = @session.execute('SELECT version FROM schema_migrations')
        result.map { |row| row['version'] }
      end

      # Get list of applied migrations with details
      # @return [Array<Hash>] Array of migration records
      def get_applied_migrations
        result = @session.execute('SELECT version, name, applied_at FROM schema_migrations')
        result.to_a
      end

      # Record a migration as applied
      # @param version [String] Migration version
      # @param name [String] Migration name
      def record_migration(version, name)
        @session.execute(
          'INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)',
          version, name, Time.now
        )
      end

      # Remove a migration record
      # @param version [String] Migration version
      def remove_migration_record(version)
        @session.execute('DELETE FROM schema_migrations WHERE version = ?', version)
      end

      # Run a migration file
      # @param file_path [String] Path to migration file
      # @param direction [Symbol] :up or :down
      def run_migration_file(file_path, direction)
        # Load the migration file
        require file_path
        
        # Get the migration class name from file name
        class_name = File.basename(file_path, '.rb').split('_')[1..-1].join('_').camelize
        migration_class = Object.const_get("#{class_name}Migration")
        
        # Run the migration
        migration = migration_class.new(@session)
        case direction
        when :up
          migration.migrate!
        when :down
          migration.rollback!
        end
      end

      # Find all migration files
      # @return [Array<String>] Array of migration file paths
      def find_migration_files
        Dir.glob(File.join(migrations_path, '*_*.rb'))
      end

      # Extract version from filename
      # @param filename [String] Migration filename
      # @return [String] Version string
      def extract_version_from_filename(filename)
        File.basename(filename).match(/^(\d+)_/)[1]
      end

      # Get migrations directory path
      # @return [String] Path to migrations directory
      def migrations_path
        File.join(Dir.pwd, 'db', 'migrations')
      end
    end
  end
end