# Configuration Guide

Cassandra-CPP provides extensive configuration options to optimize your connection for different use cases. This guide covers all configuration aspects from basic setup to advanced tuning.

## Table of Contents

- [Basic Configuration](#basic-configuration)
- [Connection Options](#connection-options)
- [Authentication](#authentication)
- [SSL/TLS Configuration](#ssltls-configuration)
- [Connection Pooling](#connection-pooling)
- [Retry Policies](#retry-policies)
- [Load Balancing](#load-balancing)
- [Compression](#compression)
- [Timeouts](#timeouts)
- [Environment-Based Configuration](#environment-based-configuration)
- [Configuration Files](#configuration-files)
- [Best Practices](#best-practices)

## Basic Configuration

The simplest configuration connects to a local Cassandra instance:

```ruby
require 'cassandra_cpp'

# Basic configuration
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['127.0.0.1']
  config.keyspace = 'my_keyspace'
end

# Or using a hash
cluster = CassandraCpp::Cluster.build(
  hosts: ['127.0.0.1'],
  keyspace: 'my_keyspace'
)
```

## Connection Options

### Contact Points

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Single host
  config.hosts = ['192.168.1.1']
  
  # Multiple hosts for redundancy
  config.hosts = ['192.168.1.1', '192.168.1.2', '192.168.1.3']
  
  # With custom ports
  config.hosts = ['192.168.1.1:9043', '192.168.1.2:9044']
  
  # Default port for all hosts
  config.port = 9042
end
```

### Datacenter Awareness

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['10.0.0.1', '10.0.0.2']
  
  # Prefer local datacenter
  config.load_balancing_policy = :dc_aware_round_robin
  config.local_datacenter = 'us-east-1'
  
  # Allow remote datacenter queries
  config.used_hosts_per_remote_dc = 2
  config.allow_remote_dcs_for_local_cl = true
end
```

### Protocol Version

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Specify protocol version (auto-negotiated by default)
  config.protocol_version = 4  # For Cassandra 2.2+
  
  # Or let the driver negotiate
  config.protocol_version = :auto  # Default
end
```

## Authentication

### Password Authentication

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['cassandra.example.com']
  
  # Basic authentication
  config.username = 'cassandra'
  config.password = 'cassandra'
  
  # Or use authentication provider
  config.auth_provider = :password
  config.credentials = {
    username: ENV['CASSANDRA_USER'],
    password: ENV['CASSANDRA_PASS']
  }
end
```

### Custom Authentication

```ruby
# Implement custom authentication provider
class KerberosAuthProvider < CassandraCpp::AuthProvider
  def initialize(principal, keytab)
    @principal = principal
    @keytab = keytab
  end
  
  def authenticate(authenticator)
    # Custom authentication logic
    token = generate_kerberos_token(@principal, @keytab)
    authenticator.send_response(token)
  end
end

cluster = CassandraCpp::Cluster.build do |config|
  config.auth_provider = KerberosAuthProvider.new(
    'cassandra@EXAMPLE.COM',
    '/etc/cassandra/cassandra.keytab'
  )
end
```

## SSL/TLS Configuration

### Basic SSL

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ['secure.cassandra.com']
  
  # Enable SSL
  config.ssl = true
  
  # With certificate verification
  config.ssl_options = {
    ca_file: '/path/to/ca.pem',
    verify_mode: :peer  # :none, :peer
  }
end
```

### Mutual TLS (mTLS)

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.ssl_options = {
    ca_file: '/path/to/ca.pem',
    cert_file: '/path/to/client-cert.pem',
    key_file: '/path/to/client-key.pem',
    key_password: ENV['SSL_KEY_PASSWORD'],
    verify_mode: :peer,
    verify_hostname: true
  }
end
```

### Advanced SSL Options

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.ssl_options = {
    # Certificate paths
    ca_file: '/path/to/ca.pem',
    cert_file: '/path/to/cert.pem',
    key_file: '/path/to/key.pem',
    
    # Verification
    verify_mode: :peer,
    verify_hostname: true,
    verify_depth: 3,
    
    # Cipher suites (OpenSSL format)
    cipher_suites: 'ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256',
    
    # TLS version
    min_tls_version: 'TLSv1.2',
    max_tls_version: 'TLSv1.3'
  }
end
```

## Connection Pooling

### Core Connections

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Core connections per host
  config.connections_per_local_host = 2
  config.connections_per_remote_host = 1
  
  # Maximum connections per host
  config.max_connections_per_local_host = 8
  config.max_connections_per_remote_host = 2
  
  # Connection heartbeat
  config.heartbeat_interval = 30  # seconds
  config.idle_timeout = 120       # seconds
end
```

### Request Routing

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Maximum requests per connection
  config.max_requests_per_connection = 1024
  
  # Queue size for pending requests
  config.queue_size_io = 8192
  config.queue_size_event = 8192
  
  # Request routing
  config.request_ratio = 0.5  # Local vs remote DC ratio
end
```

## Retry Policies

### Built-in Policies

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Default retry policy
  config.retry_policy = :default
  
  # Fallthrough policy (never retry)
  config.retry_policy = :fallthrough
  
  # Downgrading consistency retry policy
  config.retry_policy = :downgrading_consistency
end
```

### Custom Retry Policy

```ruby
class CustomRetryPolicy < CassandraCpp::RetryPolicy
  def on_read_timeout(query, cl, received, required, data_retrieved, retry_count)
    if retry_count < 3 && received >= required / 2
      # Retry with lower consistency
      return retry_decision(:retry, :quorum)
    end
    retry_decision(:rethrow)
  end
  
  def on_write_timeout(query, cl, type, required, received, retry_count)
    if retry_count < 2 && type == :simple
      return retry_decision(:retry, cl)
    end
    retry_decision(:rethrow)
  end
  
  def on_unavailable(query, cl, required, alive, retry_count)
    if retry_count < 1
      # Try next host
      return retry_decision(:retry_next_host, cl)
    end
    retry_decision(:rethrow)
  end
end

cluster = CassandraCpp::Cluster.build do |config|
  config.retry_policy = CustomRetryPolicy.new
end
```

## Load Balancing

### Round Robin

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Simple round robin
  config.load_balancing_policy = :round_robin
  
  # DC-aware round robin
  config.load_balancing_policy = :dc_aware_round_robin
  config.local_datacenter = 'us-west-2'
  config.used_hosts_per_remote_dc = 0  # Don't use remote DCs
end
```

### Token-Aware Routing

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Enable token-aware routing for better performance
  config.load_balancing_policy = :token_aware
  
  # With shuffling replicas
  config.token_aware_routing_shuffle_replicas = true
  
  # Combined with DC-aware
  config.load_balancing_policy = [:token_aware, :dc_aware_round_robin]
  config.local_datacenter = 'us-west-2'
end
```

### Custom Load Balancing

```ruby
class LatencyAwarePolicy < CassandraCpp::LoadBalancingPolicy
  def initialize(threshold_ms = 100)
    @threshold_ms = threshold_ms
    @host_latencies = {}
  end
  
  def plan(keyspace, statement)
    hosts = available_hosts
    
    # Sort by latency
    hosts.sort_by { |host| @host_latencies[host] || Float::INFINITY }
  end
  
  def on_host_up(host)
    @host_latencies.delete(host)
  end
  
  def on_host_down(host)
    @host_latencies.delete(host)
  end
  
  def on_response_complete(host, latency_ms)
    @host_latencies[host] = latency_ms
  end
end

cluster = CassandraCpp::Cluster.build do |config|
  config.load_balancing_policy = LatencyAwarePolicy.new(50)
end
```

## Compression

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Compression algorithms
  config.compression = :lz4      # Recommended for performance
  config.compression = :snappy   # Good compression/speed balance
  config.compression = :none     # No compression (default)
  
  # Compression threshold (bytes)
  config.compression_threshold = 1024  # Only compress if larger
end
```

## Timeouts

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Connection timeout
  config.connect_timeout = 5000  # ms
  
  # Request timeout
  config.request_timeout = 12000  # ms
  
  # Specific operation timeouts
  config.read_timeout = 12000     # ms
  config.write_timeout = 12000    # ms
  
  # Schema agreement
  config.schema_agreement_interval = 200   # ms
  config.max_schema_agreement_wait = 10000 # ms
  
  # DNS resolution
  config.resolve_timeout = 2000  # ms
end
```

## Environment-Based Configuration

### Using Environment Variables

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  config.hosts = ENV.fetch('CASSANDRA_HOSTS', '127.0.0.1').split(',')
  config.keyspace = ENV['CASSANDRA_KEYSPACE']
  config.username = ENV['CASSANDRA_USERNAME']
  config.password = ENV['CASSANDRA_PASSWORD']
  
  # Conditional configuration
  if ENV['CASSANDRA_SSL'] == 'true'
    config.ssl = true
    config.ssl_options = {
      ca_file: ENV['CASSANDRA_CA_FILE']
    }
  end
  
  # Environment-specific settings
  case ENV['RACK_ENV']
  when 'production'
    config.connections_per_local_host = 4
    config.request_timeout = 5000
  when 'development'
    config.connections_per_local_host = 1
    config.request_timeout = 30000
  end
end
```

### Rails Integration

```ruby
# config/initializers/cassandra.rb
Rails.application.config.cassandra = CassandraCpp::Cluster.build do |config|
  settings = Rails.application.config_for(:cassandra)
  
  config.hosts = settings['hosts']
  config.keyspace = settings['keyspace']
  config.username = settings['username']
  config.password = settings['password']
  
  # Rails environment specific
  if Rails.env.production?
    config.compression = :lz4
    config.connections_per_local_host = 4
  elsif Rails.env.test?
    config.keyspace = "#{settings['keyspace']}_test"
  end
end
```

## Configuration Files

### YAML Configuration

```yaml
# config/cassandra.yml
default: &default
  hosts:
    - 127.0.0.1
  port: 9042
  compression: lz4
  connections_per_local_host: 2
  request_timeout: 12000

development:
  <<: *default
  keyspace: myapp_development
  
test:
  <<: *default
  keyspace: myapp_test
  connections_per_local_host: 1

production:
  <<: *default
  hosts:
    - cassandra1.example.com
    - cassandra2.example.com
    - cassandra3.example.com
  keyspace: myapp_production
  username: <%= ENV['CASSANDRA_USERNAME'] %>
  password: <%= ENV['CASSANDRA_PASSWORD'] %>
  ssl: true
  ssl_options:
    ca_file: /etc/ssl/cassandra/ca.pem
```

Loading configuration:

```ruby
require 'yaml'
require 'erb'

config_file = File.read('config/cassandra.yml')
config_erb = ERB.new(config_file).result
config = YAML.safe_load(config_erb, aliases: true)

environment = ENV['RACK_ENV'] || 'development'
settings = config[environment]

cluster = CassandraCpp::Cluster.build(settings)
```

### JSON Configuration

```json
{
  "production": {
    "hosts": ["10.0.0.1", "10.0.0.2", "10.0.0.3"],
    "keyspace": "production_ks",
    "auth": {
      "username": "prod_user",
      "password": "secret"
    },
    "pool": {
      "connections_per_host": 4,
      "max_requests_per_connection": 1024
    },
    "timeouts": {
      "connect": 5000,
      "request": 12000
    }
  }
}
```

## Best Practices

### 1. Connection Management

```ruby
# Use connection pooling efficiently
cluster = CassandraCpp::Cluster.build do |config|
  # Start with minimal connections
  config.connections_per_local_host = 2
  config.max_connections_per_local_host = 8
  
  # Let the pool grow as needed
  config.connection_idle_timeout = 60
  config.connection_heartbeat_interval = 30
end

# Reuse cluster instances
class CassandraClient
  include Singleton
  
  attr_reader :cluster
  
  def initialize
    @cluster = CassandraCpp::Cluster.build do |config|
      # Configuration...
    end
  end
end
```

### 2. Datacenter Configuration

```ruby
# Production multi-DC setup
cluster = CassandraCpp::Cluster.build do |config|
  # Always specify local datacenter
  config.local_datacenter = ENV['AWS_REGION'] || 'us-east-1'
  
  # Control cross-DC traffic
  config.used_hosts_per_remote_dc = 0  # No cross-DC queries
  
  # Use LOCAL consistency levels
  config.consistency = :local_quorum
end
```

### 3. Security Configuration

```ruby
# Never hardcode credentials
cluster = CassandraCpp::Cluster.build do |config|
  # Use environment variables
  config.username = ENV.fetch('CASSANDRA_USER')
  config.password = ENV.fetch('CASSANDRA_PASS')
  
  # Or use credential providers
  config.credentials_provider = AWS::SecretsManager.new
  
  # Always use SSL in production
  if ENV['RACK_ENV'] == 'production'
    config.ssl = true
    config.ssl_options = {
      ca_file: ENV.fetch('CASSANDRA_CA_CERT'),
      verify_mode: :peer
    }
  end
end
```

### 4. Performance Tuning

```ruby
# Optimize for your workload
cluster = CassandraCpp::Cluster.build do |config|
  # For read-heavy workloads
  config.compression = :lz4
  config.connections_per_local_host = 4
  config.speculative_execution_policy = {
    type: :constant,
    delay: 50,  # ms
    max_executions: 2
  }
  
  # For write-heavy workloads
  config.compression = :none  # Reduce CPU overhead
  config.request_timeout = 5000
  config.consistency = :local_one  # If appropriate
end
```

### 5. Monitoring Configuration

```ruby
cluster = CassandraCpp::Cluster.build do |config|
  # Enable metrics
  config.enable_metrics = true
  
  # Custom event handler
  config.event_handler = lambda do |event|
    case event.type
    when :host_down
      logger.error "Host down: #{event.host}"
      StatsD.increment('cassandra.host.down')
    when :host_up
      logger.info "Host up: #{event.host}"
      StatsD.increment('cassandra.host.up')
    end
  end
  
  # Request tracking
  config.request_tracker = lambda do |request, response|
    StatsD.timing('cassandra.request.duration', response.duration)
    if response.error?
      StatsD.increment("cassandra.request.error.#{response.error_class}")
    end
  end
end
```

## Next Steps

- [Basic Usage](03_basic_usage.md) - Start using your configured cluster
- [Performance](07_performance.md) - Optimize your configuration
- [Troubleshooting](09_troubleshooting.md) - Debug configuration issues