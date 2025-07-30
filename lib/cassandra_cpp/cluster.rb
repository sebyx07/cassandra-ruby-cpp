# frozen_string_literal: true

module CassandraCpp
  # High-level cluster interface using native C++ bindings
  class Cluster
    def self.build(config = {})
      new(config)
    end

    def initialize(config = {})
      @config = default_config.merge(config)
      @native_cluster = nil
      validate_config!
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
        # Use native C++ implementation
        options = {
          hosts: @config[:hosts].join(','),
          port: @config[:port],
          consistency: CONSISTENCY_QUORUM
        }
        
        @native_cluster ||= NativeCluster.new(options)
        session = @native_cluster.connect(keyspace)
        Session.new(session, self)
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