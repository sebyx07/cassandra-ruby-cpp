# frozen_string_literal: true

module CassandraCpp
  module Schema
    # DDL (Data Definition Language) builders for schema operations
    module DDL
      # Table builder for creating table definitions with a fluent DSL
      class TableBuilder
        # @param table_name [String] Name of the table
        def initialize(table_name)
          @table_name = table_name
          @columns = []
          @primary_keys = []
          @clustering_keys = []
          @options = {}
        end

        # Define a UUID column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        # @option options [Boolean] :primary_key Make this column the primary key
        # @option options [Boolean] :null Allow null values (default true)
        # @option options [String, Proc] :default Default value or generator
        def uuid(name, **options)
          add_column(name, :uuid, options)
        end

        # Define a text column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def text(name, **options)
          add_column(name, :text, options)
        end

        # Define a varchar column (alias for text)
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def varchar(name, **options)
          add_column(name, :varchar, options)
        end

        # Define an integer column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def int(name, **options)
          add_column(name, :int, options)
        end

        # Define a big integer column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def bigint(name, **options)
          add_column(name, :bigint, options)
        end

        # Define a float column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def float(name, **options)
          add_column(name, :float, options)
        end

        # Define a double column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def double(name, **options)
          add_column(name, :double, options)
        end

        # Define a boolean column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def boolean(name, **options)
          add_column(name, :boolean, options)
        end

        # Define a timestamp column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def timestamp(name, **options)
          add_column(name, :timestamp, options)
        end

        # Define a blob column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def blob(name, **options)
          add_column(name, :blob, options)
        end

        # Define a list column
        # @param name [Symbol] Column name
        # @param element_type [Symbol] Type of list elements
        # @param options [Hash] Column options
        def list(name, element_type:, **options)
          add_column(name, "list<#{element_type}>", options)
        end

        # Define a set column
        # @param name [Symbol] Column name
        # @param element_type [Symbol] Type of set elements
        # @param options [Hash] Column options
        def set(name, element_type:, **options)
          add_column(name, "set<#{element_type}>", options)
        end

        # Define a map column
        # @param name [Symbol] Column name
        # @param key_type [Symbol] Type of map keys
        # @param value_type [Symbol] Type of map values
        # @param options [Hash] Column options
        def map(name, key_type:, value_type:, **options)
          add_column(name, "map<#{key_type}, #{value_type}>", options)
        end

        # Define a counter column
        # @param name [Symbol] Column name
        # @param options [Hash] Column options
        def counter(name, **options)
          add_column(name, :counter, options)
        end

        # Define a custom type column
        # @param name [Symbol] Column name
        # @param type [String, Symbol] Cassandra type
        # @param options [Hash] Column options
        def column(name, type, **options)
          add_column(name, type, options)
        end

        # Set table options
        # @param options [Hash] Table creation options
        # @option options [String] :comment Table comment
        # @option options [Hash] :compaction Compaction strategy options
        # @option options [Hash] :compression Compression options
        # @option options [Integer] :gc_grace_seconds Garbage collection grace period
        def with_options(**options)
          @options.merge!(options)
          self
        end

        # Generate the CREATE TABLE CQL statement
        # @return [String] Complete CQL CREATE TABLE statement
        def to_cql
          raise "No columns defined for table #{@table_name}" if @columns.empty?
          raise "No primary key defined for table #{@table_name}" if @primary_keys.empty?

          cql_parts = ["CREATE TABLE #{@table_name} ("]
          
          # Add column definitions
          column_definitions = @columns.map do |col|
            definition = "  #{col[:name]} #{col[:type]}"
            definition += " STATIC" if col[:options][:static]
            definition
          end
          
          cql_parts << column_definitions.join(",\n")
          
          # Add primary key definition
          if @clustering_keys.empty?
            # Simple primary key
            if @primary_keys.size == 1
              cql_parts << ",\n  PRIMARY KEY (#{@primary_keys.first})"
            else
              cql_parts << ",\n  PRIMARY KEY ((#{@primary_keys.join(', ')}))"
            end
          else
            # Composite primary key with clustering
            partition_key = @primary_keys.size == 1 ? @primary_keys.first : "(#{@primary_keys.join(', ')})"
            cql_parts << ",\n  PRIMARY KEY (#{partition_key}, #{@clustering_keys.join(', ')})"
          end
          
          cql_parts << "\n)"
          
          # Add table options
          unless @options.empty?
            option_parts = []
            
            if @options[:comment]
              option_parts << "comment = '#{@options[:comment]}'"
            end
            
            if @options[:compaction]
              compaction_map = @options[:compaction].map { |k, v| "'#{k}': '#{v}'" }.join(', ')
              option_parts << "compaction = {#{compaction_map}}"
            end
            
            if @options[:compression]
              compression_map = @options[:compression].map { |k, v| "'#{k}': '#{v}'" }.join(', ')
              option_parts << "compression = {#{compression_map}}"
            end
            
            if @options[:gc_grace_seconds]
              option_parts << "gc_grace_seconds = #{@options[:gc_grace_seconds]}"
            end
            
            if @options[:clustering_order]
              clustering_parts = @options[:clustering_order].map { |col, order| "#{col} #{order.upcase}" }
              option_parts << "clustering order by (#{clustering_parts.join(', ')})"
            end
            
            cql_parts << "\nWITH #{option_parts.join("\nAND ")}" unless option_parts.empty?
          end
          
          cql_parts.join + ";"
        end

        private

        # Add a column definition
        # @param name [Symbol] Column name
        # @param type [Symbol, String] Column type
        # @param options [Hash] Column options
        def add_column(name, type, options)
          @columns << {
            name: name,
            type: type,
            options: options
          }

          # Handle primary key designation
          if options[:primary_key]
            @primary_keys << name
          elsif options[:partition_key]
            @primary_keys << name
          elsif options[:clustering_key] || options[:clustering]
            @clustering_keys << name
          end

          self
        end
      end

      # Index builder for creating index definitions
      class IndexBuilder
        # @param table_name [String] Name of the table
        # @param column_name [String] Name of the column to index
        def initialize(table_name, column_name)
          @table_name = table_name
          @column_name = column_name
          @index_name = nil
          @options = {}
        end

        # Set custom index name
        # @param name [String] Index name
        # @return [IndexBuilder] self for chaining
        def name(name)
          @index_name = name
          self
        end

        # Create a custom index with options
        # @param options [Hash] Index creation options
        # @return [IndexBuilder] self for chaining
        def with_options(**options)
          @options.merge!(options)
          self
        end

        # Generate the CREATE INDEX CQL statement
        # @return [String] Complete CQL CREATE INDEX statement
        def to_cql
          index_name = @index_name || "#{@table_name}_#{@column_name}_idx"
          cql = "CREATE INDEX #{index_name} ON #{@table_name} (#{@column_name})"
          
          unless @options.empty?
            if @options[:using]
              cql += " USING '#{@options[:using]}'"
            end
            
            if @options[:with_options]
              option_parts = @options[:with_options].map { |k, v| "'#{k}': '#{v}'" }
              cql += " WITH OPTIONS = {#{option_parts.join(', ')}}"
            end
          end
          
          cql + ";"
        end
      end
    end
  end
end