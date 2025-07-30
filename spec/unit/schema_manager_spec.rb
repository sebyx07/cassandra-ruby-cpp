# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::Schema::Manager do
  let(:mock_session) { double('session') }
  let(:keyspace) { 'test_keyspace' }
  let(:schema_manager) { described_class.new(mock_session) }

  before do
    allow(mock_session).to receive(:keyspace).and_return(keyspace)
  end

  describe '#initialize' do
    it 'creates a schema manager with a session' do
      expect(schema_manager).to be_a(CassandraCpp::Schema::Manager)
    end
  end

  describe '#tables' do
    let(:mock_result) do
      [
        { 'table_name' => 'users' },
        { 'table_name' => 'posts' },
        { 'table_name' => 'comments' }
      ]
    end

    it 'returns list of table names' do
      expect(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace)
          SELECT table_name 
          FROM system_schema.tables 
          WHERE keyspace_name = ?
        CQL
        .and_return(mock_result)

      tables = schema_manager.tables
      expect(tables).to eq(['users', 'posts', 'comments'])
    end
  end

  describe '#table_info' do
    let(:table_name) { 'users' }
    let(:columns_result) do
      [
        { 'column_name' => 'id', 'type' => 'uuid', 'kind' => 'partition_key' },
        { 'column_name' => 'name', 'type' => 'text', 'kind' => 'regular' },
        { 'column_name' => 'email', 'type' => 'text', 'kind' => 'regular' }
      ]
    end
    let(:partition_keys_result) do
      [{ 'column_name' => 'id' }]
    end
    let(:clustering_keys_result) { [] }
    let(:indexes_result) { [] }

    before do
      allow(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT column_name, type, kind
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ?
        CQL
        .and_return(columns_result)
      
      allow(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT column_name
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ? AND kind = 'partition_key'
          ALLOW FILTERING
        CQL
        .and_return(partition_keys_result)
      
      allow(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT column_name
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ? AND kind = 'clustering'
          ALLOW FILTERING
        CQL
        .and_return(clustering_keys_result)
      
      allow(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT index_name, kind, options
          FROM system_schema.indexes 
          WHERE keyspace_name = ? AND table_name = ?
        CQL
        .and_return(indexes_result)
    end

    it 'returns comprehensive table information' do
      info = schema_manager.table_info(table_name)
      
      expect(info).to include(
        name: table_name,
        columns: [
          { name: 'id', type: 'uuid', kind: 'partition_key' },
          { name: 'name', type: 'text', kind: 'regular' },
          { name: 'email', type: 'text', kind: 'regular' }
        ],
        partition_keys: ['id'],
        clustering_keys: [],
        indexes: []
      )
    end
  end

  describe '#columns' do
    let(:table_name) { 'users' }
    let(:mock_result) do
      [
        { 'column_name' => 'id', 'type' => 'uuid', 'kind' => 'partition_key' },
        { 'column_name' => 'name', 'type' => 'text', 'kind' => 'regular' },
        { 'column_name' => 'tags', 'type' => 'set<text>', 'kind' => 'regular' }
      ]
    end

    it 'returns column definitions' do
      expect(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT column_name, type, kind
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ?
        CQL
        .and_return(mock_result)

      columns = schema_manager.columns(table_name)
      expect(columns).to eq([
        { name: 'id', type: 'uuid', kind: 'partition_key' },
        { name: 'name', type: 'text', kind: 'regular' },
        { name: 'tags', type: 'set<text>', kind: 'regular' }
      ])
    end
  end

  describe '#table_exists?' do
    it 'returns true when table exists' do
      allow(schema_manager).to receive(:tables).and_return(['users', 'posts'])
      expect(schema_manager.table_exists?('users')).to be true
    end

    it 'returns false when table does not exist' do
      allow(schema_manager).to receive(:tables).and_return(['users', 'posts'])
      expect(schema_manager.table_exists?('comments')).to be false
    end
  end

  describe '#create_table' do
    it 'creates a table using DDL builder' do
      expect(mock_session).to receive(:execute)
        .with(/CREATE TABLE test_table/)

      schema_manager.create_table('test_table') do |t|
        t.uuid :id, primary_key: true
        t.text :name
      end
    end
  end

  describe '#drop_table' do
    it 'drops a table with IF EXISTS by default' do
      expect(mock_session).to receive(:execute)
        .with('DROP TABLE IF EXISTS test_table')

      schema_manager.drop_table('test_table')
    end

    it 'drops a table without IF EXISTS when specified' do
      expect(mock_session).to receive(:execute)
        .with('DROP TABLE test_table')

      schema_manager.drop_table('test_table', if_exists: false)
    end
  end

  describe '#add_column' do
    it 'adds a column to an existing table' do
      expect(mock_session).to receive(:execute)
        .with('ALTER TABLE users ADD new_column text')

      schema_manager.add_column('users', 'new_column', :text)
    end
  end

  describe '#drop_column' do
    it 'drops a column from an existing table' do
      expect(mock_session).to receive(:execute)
        .with('ALTER TABLE users DROP old_column')

      schema_manager.drop_column('users', 'old_column')
    end
  end

  describe '#create_index' do
    it 'creates an index with default name' do
      expect(mock_session).to receive(:execute)
        .with('CREATE INDEX users_email_idx ON users (email)')

      schema_manager.create_index('users', 'email')
    end

    it 'creates an index with custom name' do
      expect(mock_session).to receive(:execute)
        .with('CREATE INDEX custom_idx ON users (email)')

      schema_manager.create_index('users', 'email', index_name: 'custom_idx')
    end
  end

  describe '#drop_index' do
    it 'drops an index' do
      expect(mock_session).to receive(:execute)
        .with('DROP INDEX test_idx')

      schema_manager.drop_index('test_idx')
    end
  end

  describe '#partition_key_columns' do
    let(:table_name) { 'users' }
    let(:mock_result) do
      [
        { 'column_name' => 'user_id' },
        { 'column_name' => 'tenant_id' }
      ]
    end

    it 'returns partition key columns in order' do
      expect(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT column_name
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ? AND kind = 'partition_key'
          ALLOW FILTERING
        CQL
        .and_return(mock_result)

      keys = schema_manager.partition_key_columns(table_name)
      expect(keys).to eq(['user_id', 'tenant_id'])
    end
  end

  describe '#clustering_key_columns' do
    let(:table_name) { 'events' }
    let(:mock_result) do
      [
        { 'column_name' => 'timestamp' },
        { 'column_name' => 'event_id' }
      ]
    end

    it 'returns clustering key columns in order' do
      expect(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT column_name
          FROM system_schema.columns 
          WHERE keyspace_name = ? AND table_name = ? AND kind = 'clustering'
          ALLOW FILTERING
        CQL
        .and_return(mock_result)

      keys = schema_manager.clustering_key_columns(table_name)
      expect(keys).to eq(['timestamp', 'event_id'])
    end
  end

  describe '#indexes' do
    let(:table_name) { 'users' }
    let(:mock_result) do
      [
        { 'index_name' => 'users_email_idx', 'kind' => 'COMPOSITES', 'options' => { 'target' => 'email' } },
        { 'index_name' => 'users_name_idx', 'kind' => 'COMPOSITES', 'options' => nil }
      ]
    end

    it 'returns index information' do
      expect(mock_session).to receive(:execute)
        .with(<<~CQL, keyspace, table_name)
          SELECT index_name, kind, options
          FROM system_schema.indexes 
          WHERE keyspace_name = ? AND table_name = ?
        CQL
        .and_return(mock_result)

      indexes = schema_manager.indexes(table_name)
      expect(indexes).to eq([
        { name: 'users_email_idx', kind: 'COMPOSITES', options: { 'target' => 'email' } },
        { name: 'users_name_idx', kind: 'COMPOSITES', options: {} }
      ])
    end
  end

  describe 'type mapping' do
    describe '#map_ruby_type_to_cassandra' do
      it 'maps Ruby types to Cassandra types' do
        expect(schema_manager.send(:map_ruby_type_to_cassandra, :uuid)).to eq('uuid')
        expect(schema_manager.send(:map_ruby_type_to_cassandra, :text)).to eq('text')
        expect(schema_manager.send(:map_ruby_type_to_cassandra, :int)).to eq('int')
        expect(schema_manager.send(:map_ruby_type_to_cassandra, :boolean)).to eq('boolean')
        expect(schema_manager.send(:map_ruby_type_to_cassandra, :timestamp)).to eq('timestamp')
      end

      it 'handles unknown types by converting to string' do
        expect(schema_manager.send(:map_ruby_type_to_cassandra, :custom_type)).to eq('custom_type')
      end
    end

    describe '#parse_cassandra_type' do
      it 'parses collection types correctly' do
        expect(schema_manager.send(:parse_cassandra_type, 'list<text>')).to eq('list<text>')
        expect(schema_manager.send(:parse_cassandra_type, 'set<int>')).to eq('set<int>')
        expect(schema_manager.send(:parse_cassandra_type, 'map<text, int>')).to eq('map<text, int>')
        expect(schema_manager.send(:parse_cassandra_type, 'frozen<list<text>>')).to eq('frozen<list<text>>')
      end

      it 'handles simple types unchanged' do
        expect(schema_manager.send(:parse_cassandra_type, 'text')).to eq('text')
        expect(schema_manager.send(:parse_cassandra_type, 'uuid')).to eq('uuid')
      end
    end
  end
end