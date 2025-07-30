# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::SessionMetrics do
  let(:metrics) { described_class.new }

  describe '#initialize' do
    it 'initializes with zero counts' do
      expect(metrics.query_count).to eq(0)
      expect(metrics.prepared_statement_count).to eq(0)
      expect(metrics.error_count).to eq(0)
      expect(metrics.batch_count).to eq(0)
      expect(metrics.async_query_count).to eq(0)
      expect(metrics.total_query_time_ms).to eq(0.0)
    end
  end

  describe '#record_query' do
    it 'increments query count' do
      metrics.record_query(10.5)
      expect(metrics.query_count).to eq(1)
    end

    it 'accumulates query time' do
      metrics.record_query(10.5)
      metrics.record_query(20.0)
      expect(metrics.total_query_time_ms).to eq(30.5)
    end

    it 'handles zero execution time' do
      metrics.record_query
      expect(metrics.query_count).to eq(1)
      expect(metrics.total_query_time_ms).to eq(0.0)
    end
  end

  describe '#record_prepared_statement' do
    it 'increments prepared statement count' do
      metrics.record_prepared_statement
      metrics.record_prepared_statement
      expect(metrics.prepared_statement_count).to eq(2)
    end
  end

  describe '#record_error' do
    it 'increments error count' do
      metrics.record_error
      metrics.record_error
      expect(metrics.error_count).to eq(2)
    end
  end

  describe '#record_batch' do
    it 'increments batch count' do
      metrics.record_batch
      expect(metrics.batch_count).to eq(1)
    end
  end

  describe '#record_async_query' do
    it 'increments async query count' do
      metrics.record_async_query
      metrics.record_async_query
      expect(metrics.async_query_count).to eq(2)
    end
  end

  describe '#average_query_time_ms' do
    it 'returns zero when no queries recorded' do
      expect(metrics.average_query_time_ms).to eq(0.0)
    end

    it 'calculates average query time' do
      metrics.record_query(10.0)
      metrics.record_query(20.0)
      metrics.record_query(30.0)
      expect(metrics.average_query_time_ms).to eq(20.0)
    end
  end

  describe '#query_time_percentile' do
    it 'returns zero when no queries recorded' do
      expect(metrics.query_time_percentile(0.95)).to eq(0.0)
    end

    it 'calculates percentiles correctly' do
      # Record query times: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
      (1..10).each { |i| metrics.record_query(i.to_f) }
      
      expect(metrics.query_time_percentile(0.50)).to be_within(1.0).of(5.5) # median (approximately)
      expect(metrics.query_time_percentile(0.90)).to be_within(1.0).of(9.0) # 90th percentile (approximately)
      expect(metrics.query_time_percentile(1.0)).to eq(10.0) # max
    end

    it 'handles single query time' do
      metrics.record_query(15.0)
      expect(metrics.query_time_percentile(0.50)).to eq(15.0)
      expect(metrics.query_time_percentile(0.95)).to eq(15.0)
    end
  end

  describe '#error_rate' do
    it 'returns zero when no operations recorded' do
      expect(metrics.error_rate).to eq(0.0)
    end

    it 'calculates error rate percentage' do
      metrics.record_query(10.0)  # 1 success
      metrics.record_query(15.0)  # 1 success  
      metrics.record_error        # 1 error
      metrics.record_error        # 1 error
      
      # 2 errors out of 4 total operations = 50%
      expect(metrics.error_rate).to eq(50.0)
    end

    it 'rounds error rate to 2 decimal places' do
      metrics.record_query(10.0)   # 1 success
      metrics.record_query(15.0)   # 1 success
      metrics.record_query(20.0)   # 1 success
      metrics.record_error         # 1 error
      
      # 1 error out of 4 total operations = 25%
      expect(metrics.error_rate).to eq(25.0)
    end
  end

  describe '#summary' do
    before do
      metrics.record_query(10.0)
      metrics.record_query(20.0)
      metrics.record_prepared_statement
      metrics.record_batch
      metrics.record_async_query
      metrics.record_error
    end

    it 'returns comprehensive metrics summary' do
      summary = metrics.summary
      
      expect(summary).to include(:queries, :performance, :errors)
      expect(summary[:queries][:total]).to eq(2)
      expect(summary[:queries][:async]).to eq(1)
      expect(summary[:queries][:batches]).to eq(1)
      expect(summary[:queries][:prepared_statements]).to eq(1)
      
      expect(summary[:performance][:total_time_ms]).to eq(30.0)
      expect(summary[:performance][:average_time_ms]).to eq(15.0)
      
      expect(summary[:errors][:count]).to eq(1)
      expect(summary[:errors][:rate_percent]).to be > 0
    end

    it 'includes percentile calculations' do
      summary = metrics.summary
      expect(summary[:performance]).to include(:p50_ms, :p95_ms, :p99_ms)
    end
  end

  describe '#reset!' do
    before do
      metrics.record_query(10.0)
      metrics.record_prepared_statement
      metrics.record_error
      metrics.record_batch
      metrics.record_async_query
    end

    it 'resets all metrics to zero' do
      metrics.reset!
      
      expect(metrics.query_count).to eq(0)
      expect(metrics.prepared_statement_count).to eq(0)
      expect(metrics.error_count).to eq(0)
      expect(metrics.batch_count).to eq(0)
      expect(metrics.async_query_count).to eq(0)
      expect(metrics.total_query_time_ms).to eq(0.0)
    end

    it 'clears query time history' do
      metrics.reset!
      expect(metrics.query_time_percentile(0.95)).to eq(0.0)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent operations safely' do
      threads = 100.times.map do
        Thread.new do
          10.times do
            metrics.record_query(rand(1.0..100.0))
            metrics.record_prepared_statement if rand < 0.1
            metrics.record_error if rand < 0.05
          end
        end
      end
      
      threads.each(&:join)
      
      expect(metrics.query_count).to eq(1000)
      expect(metrics.prepared_statement_count).to be >= 0
      expect(metrics.error_count).to be >= 0
    end
  end

  describe 'query time history management' do
    it 'limits query time history to 1000 entries' do
      1100.times { |i| metrics.record_query(i.to_f) }
      
      # Should have exactly 1000 entries (latest ones)
      expect(metrics.query_time_percentile(0.0)).to eq(100.0) # min should be 100 (1000 latest)
      expect(metrics.query_time_percentile(1.0)).to eq(1099.0) # max should be 1099
    end
  end
end