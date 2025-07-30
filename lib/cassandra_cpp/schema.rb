# frozen_string_literal: true

require_relative 'schema/ddl'
require_relative 'schema/migration'
require_relative 'schema/generator'

module CassandraCpp
  # Schema management module for Cassandra
  # 
  # This module provides functionality for managing database schemas,
  # including table introspection, schema migrations, and DDL operations.
  #
  # @example Basic usage
  #   schema = CassandraCpp::Schema.new(session)
  #   tables = schema.tables
  #   columns = schema.columns('users')
  #
  # @example Creating a table
  #   schema.create_table('users') do |t|
  #     t.uuid :id, primary_key: true
  #     t.text :name, null: false
  #     t.text :email, unique: true
  #     t.timestamp :created_at, default: 'now()'
  #   end
  module Schema
    # Core schema manager class
    class Manager
      # @param session [CassandraCpp::Session] Active Cassandra session
      # @param keyspace [String, nil] Optional keyspace override
      def initialize(session, keyspace = nil)
        @session = session 
        @keyspace = keyspace || session.keyspace
        # If still no keyspace, fall back to extracting from cluster/session context
        unless @keyspace
          @keyspace = 'system'
        end
      end

      # Get list of all tables in the current keyspace
      # @return [Array<String>] Array of table names
      def tables
        query = <<~CQL
          SELECT table_name 
          FROM system_schema.tables 
          WHERE keyspace_name = ?
        CQL
        
        result = @session.execute(query, @keyspace)
        result.map { |row| row['table_name'] }
      end

      # Get detailed information about a specific table
      # @param table_name [String] Name of the table
      # @return [Hash] Table metadata including columns, keys, and options
      def table_info(table_name)
        columns_info = columns(table_name)
        partition_keys = partition_key_columns(table_name)
        clustering_keys = clustering_key_columns(table_name)
        
        {
          name: table_name,
          columns: columns_info,
          partition_keys: partition_keys,
          clustering_keys: clustering_keys,
          indexes: indexes(table_name)
        }
      end

      # Get columns for a specific table
      # @param table_name [String] Name of the table
      # @return [Array<Hash>] Array of column definitions
      def columns(table_name)
        query = <<~CQL
          SELECT column_name, type, kind
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ?
        CQL
        
        result = @session.execute(query, @keyspace, table_name)
        result.map do |row|
          {
            name: row['column_name'],
            type: parse_cassandra_type(row['type']),
            kind: row['kind']
          }
        end
      end

      # Get partition key columns for a table
      # @param table_name [String] Name of the table
      # @return [Array<String>] Array of partition key column names
      def partition_key_columns(table_name)
        query = <<~CQL
          SELECT column_name
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ? AND kind = 'partition_key'
          ALLOW FILTERING
        CQL
        
        result = @session.execute(query, @keyspace, table_name)
        result.map { |row| row['column_name'] }
      end

      # Get clustering key columns for a table
      # @param table_name [String] Name of the table
      # @return [Array<String>] Array of clustering key column names
      def clustering_key_columns(table_name)
        query = <<~CQL
          SELECT column_name
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ? AND kind = 'clustering'
          ALLOW FILTERING
        CQL
        
        result = @session.execute(query, @keyspace, table_name)
        result.map { |row| row['column_name'] }
      end

      # Get indexes for a specific table
      # @param table_name [String] Name of the table
      # @return [Array<Hash>] Array of index definitions
      def indexes(table_name)
        query = <<~CQL
          SELECT index_name, kind, options
          FROM system_schema.indexes 
          WHERE keyspace_name = ? AND table_name = ?
        CQL
        
        result = @session.execute(query, @keyspace, table_name)
        result.map do |row|
          {
            name: row['index_name'],
            kind: row['kind'],
            options: row['options'] || {}
          }
        end
      end

      # Check if a table exists
      # @param table_name [String] Name of the table
      # @return [Boolean] true if table exists, false otherwise
      def table_exists?(table_name)
        tables.include?(table_name)
      end

      # Create a new table using DDL builder
      # @param table_name [String] Name of the table to create
      # @param block [Proc] Block defining the table schema
      # @return [void]
      def create_table(table_name, &block)
        builder = DDL::TableBuilder.new(table_name)
        builder.instance_eval(&block) if block_given?
        
        cql = builder.to_cql
        @session.execute(cql)
      end

      # Drop a table
      # @param table_name [String] Name of the table to drop
      # @param if_exists [Boolean] Add IF EXISTS clause
      # @return [void]
      def drop_table(table_name, if_exists: true)
        cql = "DROP TABLE #{'IF EXISTS ' if if_exists}#{table_name}"
        @session.execute(cql)
      end

      # Add a column to an existing table
      # @param table_name [String] Name of the table
      # @param column_name [String] Name of the column to add
      # @param column_type [Symbol] Type of the column
      # @return [void]
      def add_column(table_name, column_name, column_type)
        cassandra_type = map_ruby_type_to_cassandra(column_type)
        cql = "ALTER TABLE #{table_name} ADD #{column_name} #{cassandra_type}"
        @session.execute(cql)
      end

      # Drop a column from an existing table
      # @param table_name [String] Name of the table
      # @param column_name [String] Name of the column to drop
      # @return [void]
      def drop_column(table_name, column_name)
        cql = "ALTER TABLE #{table_name} DROP #{column_name}"
        @session.execute(cql)
      end

      # Create an index on a table
      # @param table_name [String] Name of the table
      # @param column_name [String] Name of the column to index
      # @param index_name [String, nil] Optional custom index name
      # @return [void]
      def create_index(table_name, column_name, index_name: nil)
        index_name ||= "#{table_name}_#{column_name}_idx"
        cql = "CREATE INDEX #{index_name} ON #{table_name} (#{column_name})"
        @session.execute(cql)
      end

      # Drop an index
      # @param index_name [String] Name of the index to drop
      # @return [void]
      def drop_index(index_name)
        cql = "DROP INDEX #{index_name}"
        @session.execute(cql)
      end

      private

      # Parse Cassandra type string into normalized format
      # @param type_string [String] Cassandra type string
      # @return [String] Normalized type
      def parse_cassandra_type(type_string)
        # Handle collection types
        case type_string
        when /^list<(.+)>$/
          "list<#{$1}>"
        when /^set<(.+)>$/
          "set<#{$1}>"
        when /^map<(.+),\s*(.+)>$/
          "map<#{$1}, #{$2}>"
        when /^frozen<(.+)>$/
          "frozen<#{$1}>"
        else
          type_string
        end
      end

      # Map Ruby types to Cassandra CQL types
      # @param ruby_type [Symbol] Ruby type symbol
      # @return [String] Cassandra CQL type
      def map_ruby_type_to_cassandra(ruby_type)
        type_mapping = {
          uuid: 'uuid',
          text: 'text',
          varchar: 'varchar',
          ascii: 'ascii',
          int: 'int',
          bigint: 'bigint',
          smallint: 'smallint',
          tinyint: 'tinyint',
          varint: 'varint',
          float: 'float',
          double: 'double',
          decimal: 'decimal',
          boolean: 'boolean',
          timestamp: 'timestamp',
          date: 'date',
          time: 'time',
          timeuuid: 'timeuuid',
          blob: 'blob',
          inet: 'inet',
          counter: 'counter'
        }

        type_mapping[ruby_type] || ruby_type.to_s
      end
    end

    # Factory method to create a schema manager
    # @param session [CassandraCpp::Session] Active Cassandra session
    # @param keyspace [String, nil] Optional keyspace override
    # @return [CassandraCpp::Schema::Manager] Schema manager instance
    def self.new(session, keyspace = nil)
      Manager.new(session, keyspace)
    end
  end
end