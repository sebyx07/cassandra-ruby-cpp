# frozen_string_literal: true

module CassandraCpp
  # Connection pool configuration and management
  class ConnectionPool
    DEFAULT_CONFIG = {
      # Core connection pool settings
      core_connections_per_host: 1,
      max_connections_per_host: 2,
      max_concurrent_requests_threshold: 100,
      
      # Timeout configurations
      connect_timeout: 5000,    # 5 seconds in milliseconds
      request_timeout: 12000,   # 12 seconds in milliseconds
      
      # Load balancing policy
      load_balance_policy: 'dc_aware',
      token_aware_routing: true,
      latency_aware_routing: false,
      
      # Retry policy
      retry_policy: 'default',
      retry_policy_logging: false,
      
      # Connection health monitoring
      heartbeat_interval: 30,           # 30 seconds
      connection_idle_timeout: 60,      # 60 seconds
      
      # Datacenter-aware load balancing options
      local_datacenter: nil,
      used_hosts_per_remote_dc: 0,
      allow_remote_dcs_for_local_cl: false,
      
      # Latency-aware routing settings (used when latency_aware_routing is true)
      latency_exclusion_threshold: 2.0,
      latency_scale_ms: 100,
      latency_retry_period_ms: 10000,
      latency_update_rate_ms: 100,
      latency_min_measured: 50
    }.freeze

    LOAD_BALANCE_POLICIES = %w[round_robin dc_aware].freeze
    RETRY_POLICIES = %w[default downgrading_consistency fallthrough].freeze

    attr_reader :config

    def initialize(config = {})
      @config = DEFAULT_CONFIG.merge(config)
      validate_config!
    end

    # Create a connection pool configuration for high-throughput scenarios
    # @return [ConnectionPool] Optimized configuration for high throughput
    def self.high_throughput
      new(
        core_connections_per_host: 4,
        max_connections_per_host: 8,
        max_concurrent_requests_threshold: 1000,
        latency_aware_routing: true,
        token_aware_routing: true
      )
    end

    # Create a connection pool configuration for low-latency scenarios
    # @return [ConnectionPool] Optimized configuration for low latency
    def self.low_latency
      new(
        core_connections_per_host: 2,
        max_connections_per_host: 4,
        max_concurrent_requests_threshold: 200,
        connect_timeout: 2000,       # 2 seconds
        request_timeout: 5000,       # 5 seconds
        latency_aware_routing: true,
        latency_exclusion_threshold: 1.5,
        token_aware_routing: true
      )
    end

    # Create a connection pool configuration for development/testing
    # @return [ConnectionPool] Configuration suitable for development
    def self.development
      new(
        core_connections_per_host: 1,
        max_connections_per_host: 1,
        max_concurrent_requests_threshold: 50,
        connect_timeout: 10000,      # 10 seconds - more forgiving for dev
        request_timeout: 15000,      # 15 seconds
        retry_policy_logging: true   # Enable logging in development
      )
    end

    # Update connection pool configuration
    # @param new_config [Hash] Configuration options to merge
    # @return [ConnectionPool] New connection pool instance with updated config
    def with(new_config)
      self.class.new(@config.merge(new_config))
    end

    # Get statistics about the connection pool configuration
    # @return [Hash] Statistics and configuration summary
    def stats
      {
        connections_per_host: {
          core: @config[:core_connections_per_host],
          max: @config[:max_connections_per_host]
        },
        timeouts: {
          connect_ms: @config[:connect_timeout],
          request_ms: @config[:request_timeout]
        },
        load_balancing: {
          policy: @config[:load_balance_policy],
          token_aware: @config[:token_aware_routing],
          latency_aware: @config[:latency_aware_routing]
        },
        retry_policy: @config[:retry_policy],
        health_monitoring: {
          heartbeat_interval_s: @config[:heartbeat_interval],
          idle_timeout_s: @config[:connection_idle_timeout]
        }
      }
    end

    # Convert configuration to hash suitable for native cluster initialization
    # @return [Hash] Configuration hash for native cluster
    def to_native_config
      @config.dup
    end

    private

    def validate_config!
      validate_numeric_ranges!
      validate_policy_names!
      validate_datacenter_config!
    end

    def validate_numeric_ranges!
      core_conn = @config[:core_connections_per_host]
      max_conn = @config[:max_connections_per_host]
      
      unless core_conn.positive? && max_conn.positive?
        raise ArgumentError, 'Connection counts must be positive'
      end
      
      if core_conn > max_conn
        raise ArgumentError, 'core_connections_per_host cannot exceed max_connections_per_host'
      end
      
      unless @config[:max_concurrent_requests_threshold].positive?
        raise ArgumentError, 'max_concurrent_requests_threshold must be positive'
      end
      
      unless @config[:connect_timeout].positive? && @config[:request_timeout].positive?
        raise ArgumentError, 'Timeout values must be positive'
      end
      
      unless @config[:heartbeat_interval].positive? && @config[:connection_idle_timeout].positive?
        raise ArgumentError, 'Health monitoring intervals must be positive'
      end
    end

    def validate_policy_names!
      policy = @config[:load_balance_policy]
      unless LOAD_BALANCE_POLICIES.include?(policy)
        raise ArgumentError, "Invalid load balance policy: #{policy}. Must be one of: #{LOAD_BALANCE_POLICIES.join(', ')}"
      end
      
      retry_policy = @config[:retry_policy]
      unless RETRY_POLICIES.include?(retry_policy)
        raise ArgumentError, "Invalid retry policy: #{retry_policy}. Must be one of: #{RETRY_POLICIES.join(', ')}"
      end
    end

    def validate_datacenter_config!
      return unless @config[:load_balance_policy] == 'dc_aware'
      
      used_hosts = @config[:used_hosts_per_remote_dc]
      unless used_hosts >= 0
        raise ArgumentError, 'used_hosts_per_remote_dc must be non-negative'
      end
    end
  end
end