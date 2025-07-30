# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Connection Pool Integration', type: :integration do
  let(:keyspace) { 'cassandra_cpp_test' }

  describe 'Cluster with ConnectionPool' do
    it 'creates cluster with default connection pool' do
      skip_unless_cassandra_available
      
      cluster = CassandraCpp::Cluster.new
      session = cluster.connect(keyspace)
      
      expect(session).to be_a(CassandraCpp::Session)
      expect(session.metrics).to be_a(CassandraCpp::SessionMetrics)
      
      session.close
      cluster.close
    end

    it 'creates cluster with custom connection pool' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        core_connections_per_host: 2,
        max_connections_per_host: 4,
        connect_timeout: 8000,
        request_timeout: 10000
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      expect(session).to be_a(CassandraCpp::Session)
      session.close
      cluster.close
    end

    it 'uses high-throughput preset configuration' do
      skip_unless_cassandra_available
      
      cluster = CassandraCpp.cluster_with_preset(:high_throughput)
      session = cluster.connect(keyspace)
      
      expect(session).to be_a(CassandraCpp::Session)
      
      # Verify the configuration is applied
      stats = cluster.connection_pool_stats
      expect(stats[:connections_per_host][:core]).to eq(4)
      expect(stats[:connections_per_host][:max]).to eq(8)
      expect(stats[:load_balancing][:latency_aware]).to be true
      
      session.close
      cluster.close
    end

    it 'uses low-latency preset configuration' do
      skip_unless_cassandra_available
      
      cluster = CassandraCpp.cluster_with_preset(:low_latency)
      session = cluster.connect(keyspace)
      
      expect(session).to be_a(CassandraCpp::Session)
      
      # Verify the configuration is applied
      stats = cluster.connection_pool_stats
      expect(stats[:connections_per_host][:core]).to eq(2)
      expect(stats[:connections_per_host][:max]).to eq(4)
      expect(stats[:timeouts][:connect_ms]).to eq(2000)
      expect(stats[:timeouts][:request_ms]).to eq(5000)
      
      session.close
      cluster.close
    end

    it 'uses development preset configuration' do
      skip_unless_cassandra_available
      
      cluster = CassandraCpp.cluster_with_preset(:development)
      session = cluster.connect(keyspace)
      
      expect(session).to be_a(CassandraCpp::Session)
      
      # Verify the configuration is applied
      stats = cluster.connection_pool_stats
      expect(stats[:connections_per_host][:core]).to eq(1)
      expect(stats[:connections_per_host][:max]).to eq(1)
      expect(stats[:timeouts][:connect_ms]).to eq(10000)
      expect(stats[:timeouts][:request_ms]).to eq(15000)
      
      session.close
      cluster.close
    end
  end

  describe 'Load Balancing Policies' do
    it 'configures round-robin load balancing' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        load_balance_policy: 'round_robin'
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Verify we can execute queries with round-robin policy
      result = session.execute('SELECT release_version FROM system.local')  
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end

    it 'configures datacenter-aware load balancing' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        load_balance_policy: 'dc_aware',
        used_hosts_per_remote_dc: 1,
        allow_remote_dcs_for_local_cl: false
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Verify we can execute queries with DC-aware policy
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end

    it 'enables token-aware routing' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        token_aware_routing: true
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Verify token-aware routing works with table queries
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end

    it 'enables latency-aware routing' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        latency_aware_routing: true,
        latency_exclusion_threshold: 2.0,
        latency_scale_ms: 100,
        latency_retry_period_ms: 10000,
        latency_update_rate_ms: 100,
        latency_min_measured: 50
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Verify latency-aware routing works
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end
  end

  describe 'Retry Policies' do
    it 'configures default retry policy' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        retry_policy: 'default'
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Should handle normal queries fine
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end

    it 'configures fallthrough retry policy' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        retry_policy: 'fallthrough'
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Should still work for normal queries
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end

    it 'enables retry policy logging' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        retry_policy: 'default',
        retry_policy_logging: true
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Normal operation should work
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end
  end

  describe 'Connection Health Monitoring' do
    it 'configures heartbeat interval' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.new(
        heartbeat_interval: 15,  # 15 seconds
        connection_idle_timeout: 120  # 2 minutes
      )
      
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      session = cluster.connect(keyspace)
      
      # Verify connection works
      result = session.execute('SELECT release_version FROM system.local')
      expect(result.first).to have_key('release_version')
      
      session.close
      cluster.close
    end
  end

  describe 'Session Metrics Integration' do
    let(:cluster) { create_test_cluster }
    let(:session) { cluster.connect(keyspace) }

    after do
      session&.close
      cluster&.close
    end

    it 'tracks query metrics' do
      skip_unless_cassandra_available
      
      initial_count = session.metrics.query_count
      
      session.execute('SELECT release_version FROM system.local')
      session.execute('SELECT release_version FROM system.local')
      
      expect(session.metrics.query_count).to eq(initial_count + 2)
      expect(session.metrics.total_query_time_ms).to be > 0
      expect(session.metrics.average_query_time_ms).to be > 0
    end

    it 'tracks prepared statement metrics' do
      skip_unless_cassandra_available
      setup_test_tables(session)
      
      initial_count = session.metrics.prepared_statement_count
      
      # First parameterized query will create a prepared statement
      session.execute('SELECT * FROM users WHERE id = ?', CassandraCpp::Uuid.generate)
      
      expect(session.metrics.prepared_statement_count).to eq(initial_count + 1)
      
      # Second parameterized query with same pattern should reuse prepared statement
      session.execute('SELECT * FROM users WHERE id = ?', CassandraCpp::Uuid.generate)
      
      expect(session.metrics.prepared_statement_count).to eq(initial_count + 1) # No increase
    end

    it 'tracks batch metrics' do
      skip_unless_cassandra_available
      setup_test_tables(session)
      
      initial_count = session.metrics.batch_count
      
      batch = session.batch(:logged)
      user_id = CassandraCpp::Uuid.generate
      batch.add("INSERT INTO users (id, name) VALUES (?, ?)", [user_id, 'Test User'])
      batch.execute
      
      expect(session.metrics.batch_count).to eq(initial_count + 1)
    end

    it 'tracks async query metrics' do
      skip_unless_cassandra_available
      
      initial_count = session.metrics.async_query_count
      
      future = session.execute_async('SELECT release_version FROM system.local')
      result = future.value
      
      expect(session.metrics.async_query_count).to eq(initial_count + 1)
      expect(result.first).to have_key('release_version')
    end

    it 'tracks error metrics' do
      skip_unless_cassandra_available
      
      initial_count = session.metrics.error_count
      
      expect {
        session.execute('INVALID QUERY SYNTAX')
      }.to raise_error(CassandraCpp::Error)
      
      expect(session.metrics.error_count).to eq(initial_count + 1)
    end

    it 'provides comprehensive metrics summary' do
      skip_unless_cassandra_available
      setup_test_tables(session)
      
      # Perform various operations
      session.execute('SELECT release_version FROM system.local')
      session.execute('SELECT * FROM users WHERE id = ?', CassandraCpp::Uuid.generate)
      
      batch = session.batch(:logged)
      batch.add("INSERT INTO users (id, name) VALUES (?, ?)", [CassandraCpp::Uuid.generate, 'Batch User'])
      batch.execute
      
      future = session.execute_async('SELECT release_version FROM system.local')
      future.value
      
      # Get summary
      summary = session.metrics.summary
      
      expect(summary).to include(:queries, :performance, :errors)
      expect(summary[:queries][:total]).to be >= 2
      expect(summary[:queries][:async]).to be >= 1
      expect(summary[:queries][:batches]).to be >= 1
      expect(summary[:queries][:prepared_statements]).to be >= 1
      expect(summary[:performance][:total_time_ms]).to be > 0
    end
  end

  describe 'Connection Pool Statistics' do
    it 'provides cluster connection pool statistics' do
      skip_unless_cassandra_available
      
      pool = CassandraCpp::ConnectionPool.high_throughput
      cluster = CassandraCpp::Cluster.with_connection_pool(pool)
      
      stats = cluster.connection_pool_stats
      
      expect(stats).to include(:connections_per_host, :timeouts, :load_balancing, :retry_policy, :health_monitoring, :cluster_config)
      expect(stats[:connections_per_host][:core]).to eq(4)
      expect(stats[:connections_per_host][:max]).to eq(8)
      expect(stats[:cluster_config]).to include(:hosts, :port)
      
      cluster.close
    end

    it 'updates connection pool configuration dynamically' do
      skip_unless_cassandra_available
      
      original_cluster = CassandraCpp::Cluster.new
      original_stats = original_cluster.connection_pool_stats
      
      expect(original_stats[:connections_per_host][:core]).to eq(1)
      
      # Create new cluster with updated pool config
      updated_cluster = original_cluster.with_connection_pool_config(
        core_connections_per_host: 3,
        max_connections_per_host: 6
      )
      
      updated_stats = updated_cluster.connection_pool_stats
      expect(updated_stats[:connections_per_host][:core]).to eq(3)
      expect(updated_stats[:connections_per_host][:max]).to eq(6)
      
      # Original cluster should be unchanged
      expect(original_cluster.connection_pool_stats[:connections_per_host][:core]).to eq(1)
      
      original_cluster.close
      updated_cluster.close
    end
  end

  private

  def setup_test_tables(session)
    session.execute(<<~CQL)
      CREATE TABLE IF NOT EXISTS users (
        id uuid PRIMARY KEY,
        name text,
        email text,
        created_at timestamp
      )
    CQL
  end
end