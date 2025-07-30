# frozen_string_literal: true

require 'logger'
require_relative 'cassandra_cpp/version'

# Main module for Cassandra-CPP
module CassandraCpp
  class Error < StandardError; end
  class ConnectionError < Error; end
  class QueryError < Error; end
  class TimeoutError < Error; end

  # Load native extension
  begin
    require_relative 'cassandra_cpp/cassandra_cpp'
    NATIVE_EXTENSION_LOADED = true
  rescue LoadError => e
    NATIVE_EXTENSION_LOADED = false
    warn "CassandraCpp: Native extension not available, falling back to pure Ruby implementation"
    warn "CassandraCpp: #{e.message}"
  end
  
  autoload :ConnectionPool, File.expand_path('cassandra_cpp/connection_pool', __dir__)
  autoload :Cluster, File.expand_path('cassandra_cpp/cluster', __dir__)
  autoload :Session, File.expand_path('cassandra_cpp/session', __dir__)
  autoload :SessionMetrics, File.expand_path('cassandra_cpp/session_metrics', __dir__)
  autoload :Result, File.expand_path('cassandra_cpp/result', __dir__)
  autoload :PreparedStatement, File.expand_path('cassandra_cpp/prepared_statement', __dir__)
  autoload :Statement, File.expand_path('cassandra_cpp/statement', __dir__)
  autoload :Batch, File.expand_path('cassandra_cpp/batch', __dir__)
  autoload :Future, File.expand_path('cassandra_cpp/future', __dir__)
  autoload :Uuid, File.expand_path('cassandra_cpp/uuid', __dir__)
  autoload :Schema, File.expand_path('cassandra_cpp/schema', __dir__)
  autoload :Model, File.expand_path('cassandra_cpp/model', __dir__)

  class << self
    attr_accessor :logger
    
    def configure
      yield self if block_given?
    end
    
    def native_extension_loaded?
      NATIVE_EXTENSION_LOADED
    end
    
    # Quick cluster creation with connection pool presets
    # @param preset [Symbol] Preset name (:high_throughput, :low_latency, :development)
    # @param config [Hash] Additional cluster configuration
    # @return [Cluster] Configured cluster instance
    def cluster_with_preset(preset, config = {})
      pool = case preset
             when :high_throughput
               ConnectionPool.high_throughput
             when :low_latency
               ConnectionPool.low_latency
             when :development
               ConnectionPool.development
             else
               raise ArgumentError, "Unknown preset: #{preset}. Use :high_throughput, :low_latency, or :development"
             end
      
      Cluster.with_connection_pool(pool, config)
    end
    
    # Create cluster with custom connection pool configuration
    # @param pool_config [Hash] Connection pool configuration
    # @param cluster_config [Hash] Cluster configuration
    # @return [Cluster] Configured cluster instance
    def cluster_with_pool(pool_config, cluster_config = {})
      pool = ConnectionPool.new(pool_config)
      Cluster.with_connection_pool(pool, cluster_config)
    end
  end

  # Default logger
  self.logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
end