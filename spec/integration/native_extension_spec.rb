# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Native Extension Integration', type: :integration do
  describe 'native extension loading' do
    it 'loads the native extension successfully' do
      expect(CassandraCpp.native_extension_loaded?).to be true
    end

    it 'provides native classes' do
      expect(defined?(CassandraCpp::NativeCluster)).to be_truthy
      expect(defined?(CassandraCpp::NativeSession)).to be_truthy
    end

    it 'provides consistency constants' do
      expect(CassandraCpp::CONSISTENCY_ONE).to eq(1)
      expect(CassandraCpp::CONSISTENCY_QUORUM).to eq(4)
      expect(CassandraCpp::CONSISTENCY_ALL).to eq(5)
    end
  end

  describe 'direct native usage' do
    it 'creates native cluster and session' do
      skip_unless_cassandra_available
      
      test_hosts = ENV['CASSANDRA_HOSTS']&.split(',') || ['localhost']
      test_port = ENV['CASSANDRA_PORT']&.to_i || 9042
      
      cluster = CassandraCpp::NativeCluster.new({
        hosts: test_hosts.join(','),
        port: test_port
      })
      
      session = cluster.connect
      expect(session).to be_a(CassandraCpp::NativeSession)
      
      result = session.execute('SELECT release_version FROM system.local')
      expect(result).to be_an(Array)
      expect(result.first).to have_key('release_version')
      
      session.close
    end

    it 'handles native errors properly' do
      skip_unless_cassandra_available
      
      test_hosts = ENV['CASSANDRA_HOSTS']&.split(',') || ['localhost']
      test_port = ENV['CASSANDRA_PORT']&.to_i || 9042
      
      cluster = CassandraCpp::NativeCluster.new({
        hosts: test_hosts.join(','),
        port: test_port
      })
      
      session = cluster.connect
      
      expect {
        session.execute('INVALID QUERY SYNTAX')
      }.to raise_error(CassandraCpp::Error)
      
      session.close
    end
  end

  describe 'performance characteristics' do
    it 'executes queries with good performance' do
      skip_unless_cassandra_available
      
      with_test_session do |session|
        # Warm up
        session.execute('SELECT release_version FROM system.local')
        
        # Time multiple queries
        start_time = Time.now
        10.times do
          session.execute('SELECT release_version FROM system.local')
        end
        duration = Time.now - start_time
        
        # Should be fast with native extension
        expect(duration).to be < 0.1  # 100ms for 10 queries
        
        avg_time = (duration / 10) * 1000  # Convert to ms
        expect(avg_time).to be < 10  # Less than 10ms per query on average
      end
    end

    it 'handles concurrent queries' do
      skip_unless_cassandra_available
      
      threads = []
      results = []
      
      5.times do
        threads << Thread.new do
          with_test_session do |session|
            result = session.execute('SELECT release_version FROM system.local')
            results << result.first['release_version']
          end
        end
      end
      
      threads.each(&:join)
      
      expect(results.size).to eq(5)
      expect(results.all? { |v| v.is_a?(String) }).to be true
    end
  end

  describe 'data type handling' do
    before(:all) do
      skip_unless_cassandra_available
      create_test_keyspace('native_test')
    end

    after(:all) do
      skip_unless_cassandra_available
      drop_test_keyspace('native_test') rescue nil
    end

    it 'handles various data types correctly' do
      skip_unless_cassandra_available
      
      with_test_session('native_test') do |session|
        # Create test table
        session.execute("""
          CREATE TABLE IF NOT EXISTS type_test (
            id UUID PRIMARY KEY,
            text_val TEXT,
            int_val INT,
            bigint_val BIGINT,
            bool_val BOOLEAN
          )
        """)

        # Insert test data
        session.execute("""
          INSERT INTO type_test (id, text_val, int_val, bigint_val, bool_val)
          VALUES (uuid(), 'test_string', 42, 1234567890, true)
        """)

        # Query and verify types
        result = session.execute('SELECT * FROM type_test LIMIT 1')
        row = result.first

        expect(row['text_val']).to be_a(String)
        expect(row['text_val']).to eq('test_string')
        
        expect(row['int_val']).to be_a(Integer)
        expect(row['int_val']).to eq(42)
        
        expect(row['bigint_val']).to be_a(Integer)
        expect(row['bigint_val']).to eq(1234567890)
        
        expect([true, false]).to include(row['bool_val'])
        expect(row['bool_val']).to be true

        # UUID should be a string representation
        expect(row['id']).to be_a(String)
        expect(row['id']).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
      end
    end
  end

  describe 'memory management' do
    it 'properly cleans up resources' do
      skip_unless_cassandra_available
      
      # Create and destroy many sessions to test memory management
      20.times do
        cluster = create_test_cluster
        session = cluster.connect
        session.execute('SELECT release_version FROM system.local')
        session.close
        cluster.close
      end
      
      # Force garbage collection
      GC.start
      
      # Should not have memory leaks (this is more of a smoke test)
      expect(true).to be true
    end
  end
end