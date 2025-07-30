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
  
  autoload :Cluster, File.expand_path('cassandra_cpp/cluster', __dir__)
  autoload :Session, File.expand_path('cassandra_cpp/session', __dir__)
  autoload :Result, File.expand_path('cassandra_cpp/result', __dir__)
  autoload :PreparedStatement, File.expand_path('cassandra_cpp/prepared_statement', __dir__)
  autoload :Statement, File.expand_path('cassandra_cpp/statement', __dir__)
  autoload :Batch, File.expand_path('cassandra_cpp/batch', __dir__)
  autoload :Future, File.expand_path('cassandra_cpp/future', __dir__)
  autoload :Uuid, File.expand_path('cassandra_cpp/uuid', __dir__)
  autoload :Model, File.expand_path('cassandra_cpp/model', __dir__)

  class << self
    attr_accessor :logger
    
    def configure
      yield self if block_given?
    end
    
    def native_extension_loaded?
      NATIVE_EXTENSION_LOADED
    end
  end

  # Default logger
  self.logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
end