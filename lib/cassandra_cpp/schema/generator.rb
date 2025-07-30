# frozen_string_literal: true

require 'fileutils'

module CassandraCpp
  module Schema
    # Generator for creating migration files and other schema-related files
    class Generator
      # Generate a new migration file
      # @param name [String] Name of the migration (snake_case)
      # @param options [Hash] Generation options
      # @option options [String] :path Custom path for migrations (default: db/migrations)
      # @return [String] Path to the generated file
      def self.migration(name, options = {})
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        filename = "#{timestamp}_#{name}.rb"
        path = options[:path] || File.join(Dir.pwd, 'db', 'migrations')
        
        FileUtils.mkdir_p(path)
        file_path = File.join(path, filename)
        
        class_name = name.split('_').map(&:capitalize).join
        
        content = generate_migration_template(class_name, name)
        
        File.write(file_path, content)
        file_path
      end

      # Generate a table creation migration
      # @param table_name [String] Name of the table
      # @param columns [Array<Hash>] Column definitions
      # @param options [Hash] Generation options
      # @return [String] Path to the generated file
      def self.create_table_migration(table_name, columns = [], options = {})
        name = "create_#{table_name}"
        timestamp = Time.now.strftime('%Y%m%d%H%M%S')
        filename = "#{timestamp}_#{name}.rb"
        path = options[:path] || File.join(Dir.pwd, 'db', 'migrations')
        
        FileUtils.mkdir_p(path)
        file_path = File.join(path, filename)
        
        class_name = name.split('_').map(&:capitalize).join
        
        content = generate_table_migration_template(class_name, table_name, columns)
        
        File.write(file_path, content)
        file_path
      end

      private

      # Generate basic migration template
      # @param class_name [String] Class name for the migration
      # @param migration_name [String] Snake case migration name
      # @return [String] Migration file content
      def self.generate_migration_template(class_name, migration_name)
        <<~RUBY
          # frozen_string_literal: true

          class #{class_name}Migration < CassandraCpp::Schema::Migration
            def up
              # Add your forward migration logic here
              # Example:
              # create_table :example do |t|
              #   t.uuid :id, primary_key: true
              #   t.text :name, null: false
              #   t.timestamp :created_at, default: 'now()'
              # end
            end

            def down
              # Add your rollback migration logic here
              # Example:
              # drop_table :example
            end
          end
        RUBY
      end

      # Generate table creation migration template
      # @param class_name [String] Class name for the migration
      # @param table_name [String] Name of the table
      # @param columns [Array<Hash>] Column definitions
      # @return [String] Migration file content
      def self.generate_table_migration_template(class_name, table_name, columns)
        column_definitions = if columns.empty?
          [
            "      t.uuid :id, primary_key: true",
            "      t.timestamp :created_at, default: 'now()'",
            "      t.timestamp :updated_at"
          ].join("\n")
        else
          columns.map do |col|
            options_str = col[:options] ? ", #{col[:options].map { |k, v| "#{k}: #{v.inspect}" }.join(', ')}" : ""
            "      t.#{col[:type]} :#{col[:name]}#{options_str}"
          end.join("\n")
        end

        <<~RUBY
          # frozen_string_literal: true

          class #{class_name}Migration < CassandraCpp::Schema::Migration
            def up
              create_table :#{table_name} do |t|
          #{column_definitions}
              end
            end

            def down
              drop_table :#{table_name}
            end
          end
        RUBY
      end
    end

    # CLI helper for generating migrations from command line
    class CLI
      # Generate migration from command line arguments
      # @param args [Array<String>] Command line arguments
      def self.generate(args)
        case args[0]
        when 'migration'
          if args[1].nil?
            puts "Usage: generate migration <name>"
            return
          end
          
          file_path = Generator.migration(args[1])
          puts "Created migration: #{file_path}"
          
        when 'create_table'
          if args[1].nil?
            puts "Usage: generate create_table <table_name> [column:type ...]"
            return
          end
          
          table_name = args[1]
          columns = parse_column_args(args[2..-1])
          
          file_path = Generator.create_table_migration(table_name, columns)
          puts "Created table migration: #{file_path}"
          
        else
          puts <<~HELP
            Available generators:
              migration <name>                    - Generate blank migration
              create_table <name> [column:type]   - Generate table creation migration
            
            Examples:
              generate migration add_email_to_users
              generate create_table users id:uuid name:text email:text
          HELP
        end
      end

      private

      # Parse column arguments from command line
      # @param args [Array<String>] Column arguments
      # @return [Array<Hash>] Parsed column definitions
      def self.parse_column_args(args)
        args.map do |arg|
          name, type = arg.split(':')
          next unless name && type
          
          options = {}
          if name == 'id' && type == 'uuid'
            options[:primary_key] = true
          end
          
          {
            name: name,
            type: type.to_sym,
            options: options
          }
        end.compact
      end
    end
  end
end