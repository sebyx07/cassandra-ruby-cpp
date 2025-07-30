# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::Schema::DDL::TableBuilder do
  let(:table_builder) { described_class.new('users') }

  describe '#initialize' do
    it 'creates a table builder with table name' do
      expect(table_builder.instance_variable_get(:@table_name)).to eq('users')
      expect(table_builder.instance_variable_get(:@columns)).to eq([])
      expect(table_builder.instance_variable_get(:@primary_keys)).to eq([])
    end
  end

  describe 'column definition methods' do
    it 'defines uuid columns' do
      table_builder.uuid(:id, primary_key: true)
      columns = table_builder.instance_variable_get(:@columns)
      
      expect(columns).to include(
        name: :id,
        type: :uuid,
        options: { primary_key: true }
      )
    end

    it 'defines text columns' do
      table_builder.text(:name, null: false)
      columns = table_builder.instance_variable_get(:@columns)
      
      expect(columns).to include(
        name: :name,
        type: :text,
        options: { null: false }
      )
    end

    it 'defines integer columns' do
      table_builder.int(:age)
      columns = table_builder.instance_variable_get(:@columns)
      
      expect(columns).to include(
        name: :age,
        type: :int,
        options: {}
      )
    end

    it 'defines timestamp columns' do
      table_builder.timestamp(:created_at, default: 'now()')
      columns = table_builder.instance_variable_get(:@columns)
      
      expect(columns).to include(
        name: :created_at,
        type: :timestamp,
        options: { default: 'now()' }
      )
    end

    it 'defines collection columns' do
      table_builder.list(:tags, element_type: :text)
      table_builder.set(:categories, element_type: :text)
      table_builder.map(:metadata, key_type: :text, value_type: :text)
      
      columns = table_builder.instance_variable_get(:@columns)
      
      expect(columns).to include(
        { name: :tags, type: 'list<text>', options: {} },
        { name: :categories, type: 'set<text>', options: {} },
        { name: :metadata, type: 'map<text, text>', options: {} }
      )
    end

    it 'defines custom type columns' do
      table_builder.column(:custom_field, 'frozen<list<text>>', null: false)
      columns = table_builder.instance_variable_get(:@columns)
      
      expect(columns).to include(
        name: :custom_field,
        type: 'frozen<list<text>>',
        options: { null: false }
      )
    end
  end

  describe 'primary key handling' do
    it 'handles single primary key' do
      table_builder.uuid(:id, primary_key: true)
      primary_keys = table_builder.instance_variable_get(:@primary_keys)
      
      expect(primary_keys).to eq([:id])
    end

    it 'handles composite primary key' do
      table_builder.uuid(:tenant_id, partition_key: true)
      table_builder.uuid(:user_id, partition_key: true)
      table_builder.timestamp(:created_at, clustering_key: true)
      
      primary_keys = table_builder.instance_variable_get(:@primary_keys)
      clustering_keys = table_builder.instance_variable_get(:@clustering_keys)
      
      expect(primary_keys).to eq([:tenant_id, :user_id])
      expect(clustering_keys).to eq([:created_at])
    end
  end

  describe '#with_options' do
    it 'sets table options' do
      table_builder.with_options(
        comment: 'User table',
        compaction: { class: 'SizeTieredCompactionStrategy' },
        gc_grace_seconds: 864000
      )
      
      options = table_builder.instance_variable_get(:@options)
      expect(options).to include(
        comment: 'User table',
        compaction: { class: 'SizeTieredCompactionStrategy' },
        gc_grace_seconds: 864000
      )
    end
  end

  describe '#to_cql' do
    context 'simple table with single primary key' do
      it 'generates correct CQL' do
        table_builder.uuid(:id, primary_key: true)
        table_builder.text(:name, null: false)
        table_builder.text(:email)
        table_builder.timestamp(:created_at)
        
        cql = table_builder.to_cql
        
        expect(cql).to include('CREATE TABLE users (')
        expect(cql).to include('id uuid')
        expect(cql).to include('name text')
        expect(cql).to include('email text')
        expect(cql).to include('created_at timestamp')
        expect(cql).to include('PRIMARY KEY (id)')
        expect(cql).to end_with(');')
      end
    end

    context 'table with composite primary key' do
      it 'generates correct CQL with clustering columns' do
        table_builder.uuid(:tenant_id, partition_key: true)
        table_builder.uuid(:user_id, partition_key: true)
        table_builder.timestamp(:created_at, clustering_key: true)
        table_builder.text(:event_type, clustering_key: true)
        table_builder.text(:data)
        
        cql = table_builder.to_cql
        
        expect(cql).to include('PRIMARY KEY ((tenant_id, user_id), created_at, event_type)')
      end
    end

    context 'table with single partition key and clustering' do
      it 'generates correct CQL' do
        table_builder.uuid(:user_id, partition_key: true)
        table_builder.timestamp(:created_at, clustering_key: true)
        table_builder.text(:message)
        
        cql = table_builder.to_cql
        
        expect(cql).to include('PRIMARY KEY (user_id, created_at)')
      end
    end

    context 'table with options' do
      it 'generates CQL with table options' do
        table_builder.uuid(:id, primary_key: true)
        table_builder.text(:name)
        table_builder.with_options(
          comment: 'Test table',
          compaction: { class: 'SizeTieredCompactionStrategy', min_threshold: '4' },
          gc_grace_seconds: 864000
        )
        
        cql = table_builder.to_cql
        
        expect(cql).to include("WITH comment = 'Test table'")
        expect(cql).to include("compaction = {'class': 'SizeTieredCompactionStrategy', 'min_threshold': '4'}")
        expect(cql).to include('gc_grace_seconds = 864000')
      end
    end

    it 'raises error when no columns defined' do
      expect { table_builder.to_cql }.to raise_error(/No columns defined/)
    end

    it 'raises error when no primary key defined' do
      table_builder.text(:name)
      expect { table_builder.to_cql }.to raise_error(/No primary key defined/)
    end
  end
end

RSpec.describe CassandraCpp::Schema::DDL::IndexBuilder do
  let(:index_builder) { described_class.new('users', 'email') }

  describe '#initialize' do
    it 'creates an index builder with table and column' do
      expect(index_builder.instance_variable_get(:@table_name)).to eq('users')
      expect(index_builder.instance_variable_get(:@column_name)).to eq('email')
    end
  end

  describe '#name' do
    it 'sets custom index name' do
      index_builder.name('custom_email_idx')
      expect(index_builder.instance_variable_get(:@index_name)).to eq('custom_email_idx')
    end
  end

  describe '#with_options' do
    it 'sets index options' do
      index_builder.with_options(using: 'SASI', with_options: { mode: 'CONTAINS' })
      options = index_builder.instance_variable_get(:@options)
      
      expect(options).to include(
        using: 'SASI',
        with_options: { mode: 'CONTAINS' }
      )
    end
  end

  describe '#to_cql' do
    it 'generates basic index CQL' do
      cql = index_builder.to_cql
      expect(cql).to eq('CREATE INDEX users_email_idx ON users (email);')
    end

    it 'generates CQL with custom name' do
      index_builder.name('custom_idx')
      cql = index_builder.to_cql
      expect(cql).to eq('CREATE INDEX custom_idx ON users (email);')
    end

    it 'generates CQL with options' do
      index_builder.with_options(
        using: 'SASI',
        with_options: { mode: 'CONTAINS', analyzer_class: 'org.apache.cassandra.index.sasi.analyzer.StandardAnalyzer' }
      )
      
      cql = index_builder.to_cql
      expect(cql).to include("USING 'SASI'")
      expect(cql).to include("WITH OPTIONS = {'mode': 'CONTAINS', 'analyzer_class': 'org.apache.cassandra.index.sasi.analyzer.StandardAnalyzer'}")
    end
  end
end