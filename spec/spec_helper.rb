# frozen_string_literal: true

require 'rspec'

# Load SimpleCov if available
begin
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/vendor/'
    add_group 'Libraries', 'lib'
    add_group 'Extensions', 'ext'
  end
rescue LoadError
  # SimpleCov not available, continue without coverage
end

# Load the library
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cassandra_cpp'

# RSpec configuration
RSpec.configure do |config|
  # Use expect syntax
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  # Use expect syntax for mocks
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.syntax = :expect
  end

  # Shared examples configuration
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Output configuration
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  # Profile slow tests
  config.profile_examples = 10 if ENV['PROFILE_TESTS']

  # Test environment detection
  config.before(:suite) do
    puts "🧪 Running tests with #{CassandraCpp.native_extension_loaded? ? 'NATIVE C++' : 'Ruby fallback'} implementation"
    
    # Check Cassandra connectivity
    begin
      test_hosts = ENV['CASSANDRA_HOSTS']&.split(',') || ['localhost']
      test_port = ENV['CASSANDRA_PORT']&.to_i || 9042
      puts "📡 Testing connectivity to: #{test_hosts.join(', ')}:#{test_port}"
      
      cluster = CassandraCpp::Cluster.build(hosts: test_hosts, port: test_port)
      session = cluster.connect
      session.execute('SELECT release_version FROM system.local')
      session.close
      cluster.close
      puts "✅ Cassandra connectivity verified"
    rescue => e
      puts "⚠️  Cassandra not available: #{e.message}"
      puts "   Integration tests will be skipped"
    end
  end

  # Clean up after each test
  config.after(:each) do
    # Clean up any test artifacts
    GC.start
  end

  # Tags for different test types
  config.define_derived_metadata(file_path: %r{/spec/unit/}) do |metadata|
    metadata[:type] = :unit
  end

  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:type] = :integration
  end

  # Skip integration tests if Cassandra is not available
  config.before(:each, type: :integration) do
    begin
      test_hosts = ENV['CASSANDRA_HOSTS']&.split(',') || ['localhost']
      test_port = ENV['CASSANDRA_PORT']&.to_i || 9042
      cluster = CassandraCpp::Cluster.build(hosts: test_hosts, port: test_port)
      session = cluster.connect
      session.close
      cluster.close
    rescue CassandraCpp::ConnectionError
      skip "Cassandra is not available"
    end
  end
end

# Test helpers
module CassandraCppTestHelpers
  def create_test_cluster(options = {})
    test_hosts = ENV['CASSANDRA_HOSTS']&.split(',') || ['localhost']
    test_port = ENV['CASSANDRA_PORT']&.to_i || 9042
    
    default_options = {
      hosts: test_hosts,
      port: test_port
    }
    CassandraCpp::Cluster.build(default_options.merge(options))
  end

  def with_test_session(keyspace = nil, &block)
    cluster = create_test_cluster
    session = cluster.connect(keyspace)
    begin
      yield session
    ensure
      session.close
      cluster.close
    end
  end

  def create_test_keyspace(name = 'cassandra_cpp_test')
    with_test_session do |session|
      session.execute("DROP KEYSPACE IF EXISTS #{name}")
      session.execute("""
        CREATE KEYSPACE #{name}
        WITH REPLICATION = {
          'class': 'SimpleStrategy',
          'replication_factor': 1
        }
      """)
    end
  end

  def drop_test_keyspace(name = 'cassandra_cpp_test')
    with_test_session do |session|
      session.execute("DROP KEYSPACE IF EXISTS #{name}")
    end
  end

  def skip_unless_cassandra_available
    create_test_cluster.connect.close
  rescue CassandraCpp::ConnectionError
    skip "Cassandra is not available"
  end

  def expect_native_extension
    expect(CassandraCpp.native_extension_loaded?).to be true
  end
end

RSpec.configure do |config|
  config.include CassandraCppTestHelpers
end