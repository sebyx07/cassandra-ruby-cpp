# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::Batch do
  let(:cluster) { create_test_cluster }
  let(:session) do
    skip_unless_cassandra_available
    cluster.connect('system')
  end

  after do
    session&.close
    cluster&.close
  end

  describe '#initialize' do
    it 'creates a batch instance' do
      skip_unless_cassandra_available
      
      batch = session.batch
      expect(batch).to be_a(described_class)
    end

    it 'accepts different batch types' do
      skip_unless_cassandra_available
      
      logged_batch = session.batch(:logged)
      unlogged_batch = session.batch(:unlogged)
      counter_batch = session.batch(:counter)
      
      expect(logged_batch).to be_a(described_class)
      expect(unlogged_batch).to be_a(described_class)
      expect(counter_batch).to be_a(described_class)
    end

    it 'raises error for invalid batch type' do
      skip_unless_cassandra_available
      
      expect {
        session.batch(:invalid)
      }.to raise_error(ArgumentError, /Unknown batch type/)
    end
  end

  describe '#add' do
    let(:batch) { session.batch }

    it 'adds simple query strings' do
      skip_unless_cassandra_available
      
      expect {
        # Use a dummy INSERT - the point is to test the batch API, not execute real operations
        batch.add("INSERT INTO dummy_table (id, name) VALUES (uuid(), 'test')")
      }.not_to raise_error
    end

    it 'adds parameterized queries' do
      skip_unless_cassandra_available
      
      expect {
        # Use a dummy INSERT with parameters
        batch.add("INSERT INTO dummy_table (id, name) VALUES (?, ?)", ['123e4567-e89b-12d3-a456-426614174000', 'test'])
      }.not_to raise_error
    end

    it 'supports method chaining' do
      skip_unless_cassandra_available
      
      result = batch.add("INSERT INTO dummy_table (id, name) VALUES (uuid(), 'test')")
      expect(result).to eq(batch)
    end
  end

  describe '#statement' do
    let(:batch) { session.batch }

    it 'adds statements using fluent interface' do
      skip_unless_cassandra_available
      
      result = batch.statement("INSERT INTO dummy_table (id, name) VALUES (uuid(), 'test')")
      expect(result).to eq(batch)
    end

    it 'supports parameters' do
      skip_unless_cassandra_available
      
      expect {
        batch.statement("INSERT INTO dummy_table (id, name) VALUES (?, ?)", '123e4567-e89b-12d3-a456-426614174000', 'test')
      }.not_to raise_error
    end
  end

  describe '#consistency=' do
    let(:batch) { session.batch }

    it 'sets consistency level' do
      skip_unless_cassandra_available
      
      expect {
        batch.consistency = CassandraCpp::CONSISTENCY_ONE
      }.not_to raise_error
    end

    it 'supports method chaining with with_consistency' do
      skip_unless_cassandra_available
      
      result = batch.with_consistency(CassandraCpp::CONSISTENCY_QUORUM)
      expect(result).to eq(batch)
    end
  end

  describe '#execute', type: :integration do
    let(:batch) { session.batch }

    it 'executes batch successfully (empty batch)' do
      skip_unless_cassandra_available
      
      # Empty batch should execute without error
      result = batch.execute
      expect(result).to be_a(CassandraCpp::Result)
      expect(result.to_a).to be_empty
    end

    it 'handles empty batches' do
      skip_unless_cassandra_available
      
      result = batch.execute
      expect(result).to be_a(CassandraCpp::Result)
      expect(result.to_a).to be_empty
    end

    it 'supports fluent interface with empty batch' do
      skip_unless_cassandra_available
      
      result = session.batch
                      .with_consistency(CassandraCpp::CONSISTENCY_ONE)
                      .execute
      
      expect(result).to be_a(CassandraCpp::Result)
      expect(result.to_a).to be_empty
    end
  end

  describe 'batch types' do
    it 'creates logged batch by default' do
      skip_unless_cassandra_available
      
      batch = session.batch
      expect(batch).to be_a(described_class)
    end

    it 'creates unlogged batch when specified' do
      skip_unless_cassandra_available
      
      batch = session.batch(:unlogged)
      expect(batch).to be_a(described_class)
    end

    it 'creates counter batch when specified' do
      skip_unless_cassandra_available
      
      batch = session.batch(:counter)
      expect(batch).to be_a(described_class)
    end
  end

  describe 'constants' do
    it 'defines batch type constants' do
      expect(CassandraCpp::BATCH_TYPE_LOGGED).to be_a(Integer)
      expect(CassandraCpp::BATCH_TYPE_UNLOGGED).to be_a(Integer)
      expect(CassandraCpp::BATCH_TYPE_COUNTER).to be_a(Integer)
    end
  end
end