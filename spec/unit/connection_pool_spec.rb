# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::ConnectionPool do
  describe '.new' do
    it 'creates a connection pool with default configuration' do
      pool = described_class.new
      expect(pool.config[:core_connections_per_host]).to eq(1)
      expect(pool.config[:max_connections_per_host]).to eq(2)
      expect(pool.config[:load_balance_policy]).to eq('dc_aware')
      expect(pool.config[:retry_policy]).to eq('default')
    end

    it 'accepts custom configuration' do
      config = {
        core_connections_per_host: 4,
        max_connections_per_host: 8,
        load_balance_policy: 'round_robin'
      }
      pool = described_class.new(config)
      expect(pool.config[:core_connections_per_host]).to eq(4)
      expect(pool.config[:max_connections_per_host]).to eq(8)
      expect(pool.config[:load_balance_policy]).to eq('round_robin')
    end

    it 'merges custom config with defaults' do
      config = { connect_timeout: 8000 }
      pool = described_class.new(config)
      expect(pool.config[:connect_timeout]).to eq(8000)
      expect(pool.config[:core_connections_per_host]).to eq(1) # default
    end
  end

  describe 'preset configurations' do
    describe '.high_throughput' do
      let(:pool) { described_class.high_throughput }

      it 'creates a high-throughput optimized configuration' do
        expect(pool.config[:core_connections_per_host]).to eq(4)
        expect(pool.config[:max_connections_per_host]).to eq(8)
        expect(pool.config[:max_concurrent_requests_threshold]).to eq(1000)
        expect(pool.config[:latency_aware_routing]).to be true
        expect(pool.config[:token_aware_routing]).to be true
      end
    end

    describe '.low_latency' do
      let(:pool) { described_class.low_latency }

      it 'creates a low-latency optimized configuration' do
        expect(pool.config[:core_connections_per_host]).to eq(2)
        expect(pool.config[:max_connections_per_host]).to eq(4)
        expect(pool.config[:connect_timeout]).to eq(2000)
        expect(pool.config[:request_timeout]).to eq(5000)
        expect(pool.config[:latency_aware_routing]).to be true
        expect(pool.config[:latency_exclusion_threshold]).to eq(1.5)
      end
    end

    describe '.development' do
      let(:pool) { described_class.development }

      it 'creates a development-friendly configuration' do
        expect(pool.config[:core_connections_per_host]).to eq(1)
        expect(pool.config[:max_connections_per_host]).to eq(1)
        expect(pool.config[:max_concurrent_requests_threshold]).to eq(50)
        expect(pool.config[:connect_timeout]).to eq(10000)
        expect(pool.config[:request_timeout]).to eq(15000)
        expect(pool.config[:retry_policy_logging]).to be true
      end
    end
  end

  describe '#with' do
    let(:original_pool) { described_class.new }

    it 'creates a new pool with updated configuration' do
      new_pool = original_pool.with(core_connections_per_host: 2, max_connections_per_host: 4)
      expect(original_pool.config[:core_connections_per_host]).to eq(1)
      expect(new_pool.config[:core_connections_per_host]).to eq(2)
    end

    it 'preserves other configuration values' do
      new_pool = original_pool.with(connect_timeout: 8000)
      expect(new_pool.config[:max_connections_per_host]).to eq(original_pool.config[:max_connections_per_host])
      expect(new_pool.config[:retry_policy]).to eq(original_pool.config[:retry_policy])
      expect(new_pool.config[:connect_timeout]).to eq(8000)
    end
  end

  describe '#stats' do
    let(:pool) { described_class.new }

    it 'returns comprehensive configuration statistics' do
      stats = pool.stats
      expect(stats).to include(:connections_per_host, :timeouts, :load_balancing, :retry_policy, :health_monitoring)
      expect(stats[:connections_per_host][:core]).to eq(1)
      expect(stats[:connections_per_host][:max]).to eq(2)
      expect(stats[:timeouts][:connect_ms]).to eq(5000)
      expect(stats[:load_balancing][:policy]).to eq('dc_aware')
    end
  end

  describe '#to_native_config' do
    let(:pool) { described_class.new }

    it 'returns a hash suitable for native cluster configuration' do
      config = pool.to_native_config
      expect(config).to be_a(Hash)
      expect(config).to include(:core_connections_per_host, :max_connections_per_host, :load_balance_policy)
    end

    it 'does not modify the original config' do
      original_config = pool.config.dup
      config = pool.to_native_config
      config[:new_key] = 'new_value'
      expect(pool.config).to eq(original_config)
    end
  end

  describe 'validation' do
    context 'connection counts' do
      it 'validates positive connection counts' do
        expect {
          described_class.new(core_connections_per_host: 0)
        }.to raise_error(ArgumentError, /Connection counts must be positive/)

        expect {
          described_class.new(max_connections_per_host: -1)
        }.to raise_error(ArgumentError, /Connection counts must be positive/)
      end

      it 'validates core connections does not exceed max connections' do
        expect {
          described_class.new(core_connections_per_host: 5, max_connections_per_host: 3)
        }.to raise_error(ArgumentError, /core_connections_per_host cannot exceed max_connections_per_host/)
      end
    end

    context 'concurrent requests threshold' do
      it 'validates positive threshold' do
        expect {
          described_class.new(max_concurrent_requests_threshold: 0)
        }.to raise_error(ArgumentError, /max_concurrent_requests_threshold must be positive/)
      end
    end

    context 'timeout values' do
      it 'validates positive timeout values' do
        expect {
          described_class.new(connect_timeout: 0)
        }.to raise_error(ArgumentError, /Timeout values must be positive/)

        expect {
          described_class.new(request_timeout: -1000)
        }.to raise_error(ArgumentError, /Timeout values must be positive/)
      end
    end

    context 'health monitoring intervals' do
      it 'validates positive intervals' do
        expect {
          described_class.new(heartbeat_interval: 0)
        }.to raise_error(ArgumentError, /Health monitoring intervals must be positive/)

        expect {
          described_class.new(connection_idle_timeout: -30)
        }.to raise_error(ArgumentError, /Health monitoring intervals must be positive/)
      end
    end

    context 'load balance policy' do
      it 'validates known load balance policies' do
        expect {
          described_class.new(load_balance_policy: 'invalid_policy')
        }.to raise_error(ArgumentError, /Invalid load balance policy/)
      end

      it 'accepts valid load balance policies' do
        expect {
          described_class.new(load_balance_policy: 'round_robin')
        }.not_to raise_error

        expect {
          described_class.new(load_balance_policy: 'dc_aware')
        }.not_to raise_error
      end
    end

    context 'retry policy' do
      it 'validates known retry policies' do
        expect {
          described_class.new(retry_policy: 'unknown_policy')
        }.to raise_error(ArgumentError, /Invalid retry policy/)
      end

      it 'accepts valid retry policies' do
        expect {
          described_class.new(retry_policy: 'default')
        }.not_to raise_error

        expect {
          described_class.new(retry_policy: 'fallthrough')
        }.not_to raise_error
      end
    end

    context 'datacenter-aware configuration' do
      it 'validates used_hosts_per_remote_dc is non-negative' do
        expect {
          described_class.new(
            load_balance_policy: 'dc_aware',
            used_hosts_per_remote_dc: -1
          )
        }.to raise_error(ArgumentError, /used_hosts_per_remote_dc must be non-negative/)
      end

      it 'accepts valid datacenter-aware configuration' do
        expect {
          described_class.new(
            load_balance_policy: 'dc_aware',
            local_datacenter: 'dc1',
            used_hosts_per_remote_dc: 2,
            allow_remote_dcs_for_local_cl: true
          )
        }.not_to raise_error
      end
    end
  end
end