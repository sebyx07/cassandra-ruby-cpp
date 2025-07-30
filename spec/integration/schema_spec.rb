# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Schema Management Integration', type: :integration do
  let(:keyspace) { 'cassandra_cpp_test' }
  let(:cluster) { create_test_cluster }
  let(:session) { cluster.connect(keyspace) }
  let(:schema) { CassandraCpp::Schema.new(session, keyspace) }

  after do
    session&.close
    cluster&.close
  end

  describe 'Schema Manager' do
    context 'table operations' do
      before { skip_unless_cassandra_available }

      it 'creates and manages tables' do
        # Clean up any existing test table
        schema.drop_table('schema_test_users', if_exists: true)

        # Create a new table
        schema.create_table('schema_test_users') do |t|
          t.uuid :id, primary_key: true
          t.text :name, null: false
          t.text :email
          t.timestamp :created_at, default: 'now()'
          t.list :tags, element_type: :text
          t.map :metadata, key_type: :text, value_type: :text
        end

        # Verify table exists
        expect(schema.table_exists?('schema_test_users')).to be true
        expect(schema.tables).to include('schema_test_users')

        # Get table info
        table_info = schema.table_info('schema_test_users')
        expect(table_info[:name]).to eq('schema_test_users')
        expect(table_info[:partition_keys]).to eq(['id'])
        expect(table_info[:clustering_keys]).to be_empty

        # Verify columns
        columns = schema.columns('schema_test_users')
        column_names = columns.map { |col| col[:name] }
        expect(column_names).to include('id', 'name', 'email', 'created_at', 'tags', 'metadata')

        id_column = columns.find { |col| col[:name] == 'id' }
        expect(id_column[:type]).to eq('uuid')
        expect(id_column[:kind]).to eq('partition_key')

        # Clean up
        schema.drop_table('schema_test_users')
        expect(schema.table_exists?('schema_test_users')).to be false
      end

      it 'creates table with composite primary key' do
        schema.drop_table('schema_test_events', if_exists: true)

        schema.create_table('schema_test_events') do |t|
          t.uuid :tenant_id, partition_key: true
          t.uuid :user_id, partition_key: true
          t.timestamp :event_time, clustering_key: true
          t.text :event_type, clustering_key: true
          t.text :data
        end

        table_info = schema.table_info('schema_test_events')
        expect(table_info[:partition_keys]).to eq(['tenant_id', 'user_id'])
        expect(table_info[:clustering_keys]).to eq(['event_time', 'event_type'])

        schema.drop_table('schema_test_events')
      end

      it 'adds and drops columns' do
        schema.drop_table('schema_test_alter', if_exists: true)

        # Create base table
        schema.create_table('schema_test_alter') do |t|
          t.uuid :id, primary_key: true
          t.text :name
        end

        # Add a column
        schema.add_column('schema_test_alter', 'description', :text)

        # Verify column was added
        columns = schema.columns('schema_test_alter')
        column_names = columns.map { |col| col[:name] }
        expect(column_names).to include('description')

        # Drop the column
        schema.drop_column('schema_test_alter', 'description')

        # Verify column was removed
        columns = schema.columns('schema_test_alter')
        column_names = columns.map { |col| col[:name] }
        expect(column_names).not_to include('description')

        schema.drop_table('schema_test_alter')
      end

      it 'creates and drops indexes' do
        schema.drop_table('schema_test_index', if_exists: true)

        # Create table
        schema.create_table('schema_test_index') do |t|
          t.uuid :id, primary_key: true
          t.text :email
          t.text :name
        end

        # Create index
        schema.create_index('schema_test_index', 'email', index_name: 'test_email_idx')

        # Verify index exists
        indexes = schema.indexes('schema_test_index')
        expect(indexes.map { |idx| idx[:name] }).to include('test_email_idx')

        # Drop index
        schema.drop_index('test_email_idx')

        # Verify index was removed
        indexes = schema.indexes('schema_test_index')
        expect(indexes.map { |idx| idx[:name] }).not_to include('test_email_idx')

        schema.drop_table('schema_test_index')
      end
    end
  end

  describe 'DDL Builder' do
    before { skip_unless_cassandra_available }

    it 'generates complex table with options' do
      schema.drop_table('schema_test_complex', if_exists: true)

      schema.create_table('schema_test_complex') do |t|
        t.uuid :id, primary_key: true
        t.text :name, null: false
        t.int :age
        t.boolean :active
        t.timestamp :created_at, default: 'now()'
        t.list :tags, element_type: :text
        t.set :categories, element_type: :text
        t.map :metadata, key_type: :text, value_type: :text
        t.blob :data

        t.with_options(
          comment: 'Complex test table',
          gc_grace_seconds: 864000
        )
      end

      # Verify table was created successfully
      expect(schema.table_exists?('schema_test_complex')).to be true

      # Verify all columns exist with correct types
      columns = schema.columns('schema_test_complex')
      column_types = columns.each_with_object({}) { |col, hash| hash[col[:name]] = col[:type] }

      expect(column_types['id']).to eq('uuid')
      expect(column_types['name']).to eq('text')
      expect(column_types['age']).to eq('int')
      expect(column_types['active']).to eq('boolean')
      expect(column_types['created_at']).to eq('timestamp')
      expect(column_types['tags']).to eq('list<text>')
      expect(column_types['categories']).to eq('set<text>')
      expect(column_types['metadata']).to eq('map<text, text>')
      expect(column_types['data']).to eq('blob')

      schema.drop_table('schema_test_complex')
    end
  end

  describe 'Migration System' do
    before { skip_unless_cassandra_available }

    # Create a test migration class
    let(:test_migration_class) do
      Class.new(CassandraCpp::Schema::Migration) do
        def self.name
          '20240101120000_CreateTestMigrationTable'
        end

        def up
          create_table :migration_test_table do |t|
            t.uuid :id, primary_key: true
            t.text :name
            t.timestamp :created_at, default: 'now()'
          end
          
          create_index :migration_test_table, :name
        end

        def down
          drop_index 'migration_test_table_name_idx'
          drop_table :migration_test_table
        end
      end
    end

    let(:migration_runner) { CassandraCpp::Schema::MigrationRunner.new(session) }

    it 'runs migrations forward and backward' do
      # Clean up any existing data
      if schema.table_exists?('migration_test_table')
        schema.drop_table('migration_test_table')
      end

      # Create and run migration
      migration = test_migration_class.new(session)

      # Run forward migration
      migration.migrate!

      # Verify table was created
      expect(schema.table_exists?('migration_test_table')).to be true

      # Verify index was created
      indexes = schema.indexes('migration_test_table')
      expect(indexes.map { |idx| idx[:name] }).to include('migration_test_table_name_idx')

      # Run rollback migration
      migration.rollback!

      # Verify table was dropped
      expect(schema.table_exists?('migration_test_table')).to be false
    end

    it 'tracks migration versions' do
      # Ensure schema_migrations table exists and is clean
      if schema.table_exists?('schema_migrations')
        session.execute('TRUNCATE schema_migrations')
      end

      # Get initial status
      initial_status = migration_runner.status
      expect(initial_status).to be_empty

      # Record a migration manually for testing
      session.execute(
        'INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)',
        '20240101120000', 'create_test_table', Time.now
      )

      # Check applied versions
      applied = migration_runner.send(:get_applied_versions)
      expect(applied).to include('20240101120000')

      # Clean up
      session.execute('DELETE FROM schema_migrations WHERE version = ?', '20240101120000')
    end
  end

  describe 'Error handling' do
    before { skip_unless_cassandra_available }

    it 'handles invalid table operations gracefully' do
      # Try to drop non-existent table without IF EXISTS
      expect {
        schema.drop_table('non_existent_table', if_exists: false)
      }.to raise_error(CassandraCpp::Error)

      # IF EXISTS should not raise error
      expect {
        schema.drop_table('non_existent_table', if_exists: true)
      }.not_to raise_error
    end

    it 'validates table builder requirements' do
      builder = CassandraCpp::Schema::DDL::TableBuilder.new('invalid_table')
      
      # Should raise error when no columns defined
      expect { builder.to_cql }.to raise_error(/No columns defined/)

      # Should raise error when no primary key defined
      builder.text(:name)
      expect { builder.to_cql }.to raise_error(/No primary key defined/)
    end
  end

  private

  def create_test_cluster
    CassandraCpp::Cluster.new
  end
end