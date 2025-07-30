# frozen_string_literal: true

module CassandraCpp
  # High-level cluster interface using native C++ bindings
  class Cluster
    def self.build(config = {})
      new(config)
    end

    def initialize(config = {})
      @config = default_config.merge(config)
      @connection_pool = config[:connection_pool] || ConnectionPool.new
      @native_cluster = nil
      validate_config!
    end
    
    # Configure with specific connection pool settings
    # @param pool [ConnectionPool] Connection pool configuration
    # @return [Cluster] New cluster instance with the connection pool
    def self.with_connection_pool(pool, config = {})
      new(config.merge(connection_pool: pool))
    end

    def connect(keyspace = nil)
      keyspace ||= @config[:keyspace]
      
      unless CassandraCpp.native_extension_loaded?
        raise ConnectionError, "Native extension not loaded. Please ensure the gem is properly installed."
      end
      
      connect_native(keyspace)
    end

    private

    def connect_native(keyspace = nil)
      begin
        # Use native C++ implementation with connection pool configuration
        options = {
          hosts: @config[:hosts].join(','),
          port: @config[:port],
          consistency: CONSISTENCY_QUORUM
        }.merge(@connection_pool.to_native_config)
        
        @native_cluster ||= NativeCluster.new(options)
        session = @native_cluster.connect(keyspace)
        Session.new(session, self, keyspace)
      rescue CassandraCpp::Error => e
        raise ConnectionError, "Connection failed: #{e.message}"
      end
    end

    public

    def execute(query, *params)
      session = connect
      session.execute(query, *params)
    ensure
      session&.close
    end

    def close
      if @native_cluster && @native_cluster.respond_to?(:close)
        @native_cluster.close
      end
      @native_cluster = nil
    end
    
    # Get connection pool statistics and configuration
    # @return [Hash] Connection pool stats and configuration
    def connection_pool_stats
      @connection_pool.stats.merge(
        cluster_config: {
          hosts: @config[:hosts],
          port: @config[:port],
          keyspace: @config[:keyspace]
        }
      )
    end
    
    # Update connection pool configuration (creates new cluster instance)
    # @param new_pool_config [Hash] New connection pool configuration
    # @return [Cluster] New cluster instance with updated connection pool
    def with_connection_pool_config(new_pool_config)
      new_pool = @connection_pool.with(new_pool_config)
      self.class.new(@config.merge(connection_pool: new_pool))
    end

    private

    def default_config
      default_hosts = ENV['CASSANDRA_HOSTS']&.split(',') || ['127.0.0.1']
      default_port = ENV['CASSANDRA_PORT']&.to_i || 9042
      
      {
        hosts: default_hosts,
        port: default_port,
        keyspace: nil,
        username: nil,
        password: nil,
        ssl: false,
        compression: :none,
        timeout: 12,
        heartbeat_interval: 30,
        idle_timeout: 60
      }
    end

    def validate_config!
      raise ArgumentError, 'hosts must be provided' if @config[:hosts].empty?
      
      unless @config[:hosts].is_a?(Array)
        @config[:hosts] = [@config[:hosts]]
      end
      
      unless (1..65535).cover?(@config[:port])
        raise ArgumentError, 'port must be between 1 and 65535'
      end
    end
  end
end