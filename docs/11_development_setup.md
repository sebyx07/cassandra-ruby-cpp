# Development Environment Setup

This guide will help you set up a complete development environment for Cassandra-CPP, following modern Ruby development practices and SOLID principles.

## Table of Contents

- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Development Environment](#development-environment)
- [Docker Configuration](#docker-configuration)
- [Development Workflow](#development-workflow)
- [Code Quality Tools](#code-quality-tools)
- [Testing Strategy](#testing-strategy)
- [SOLID Principles Implementation](#solid-principles-implementation)
- [Performance Considerations](#performance-considerations)
- [Troubleshooting](#troubleshooting)

## Quick Start

The fastest way to get started is using our automated setup script:

```bash
# Clone the repository
git clone https://github.com/your-org/cassandra-cpp.git
cd cassandra-cpp

# Run the setup script
./bin/setup
```

This script will:
- Check and install system dependencies
- Set up the Ruby environment
- Install the DataStax C++ driver
- Configure Docker containers
- Start the Cassandra cluster
- Run initial tests

## System Requirements

### Minimum Requirements

- **Ruby**: 3.0+ (3.2+ recommended)
- **Docker**: 20.10.0+
- **Docker Compose**: 2.0.0+
- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 10GB free space

### Operating System Support

| OS | Version | Status |
|---|---|---|
| Ubuntu | 20.04+ | ✅ Fully Supported |
| macOS | 12+ | ✅ Fully Supported |
| CentOS/RHEL | 8+ | ⚠️ Community Support |
| Windows | WSL2 | ⚠️ Community Support |

### Development Tools

- **Git**: 2.20+
- **Build Tools**: gcc/clang, cmake, pkg-config
- **Text Editor**: VS Code, RubyMine, or Vim/Emacs

## Development Environment

### Ruby Version Management

We recommend using a Ruby version manager:

#### Using rbenv

```bash
# Install rbenv
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

# Install Ruby 3.2
rbenv install 3.2.2
rbenv local 3.2.2
```

#### Using asdf

```bash
# Install asdf
git clone https://github.com/asdf-vm/asdf.git ~/.asdf

# Install Ruby plugin
asdf plugin add ruby

# Install Ruby 3.2
asdf install ruby 3.2.2
asdf local ruby 3.2.2
```

### System Dependencies

#### Ubuntu/Debian

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  cmake \
  pkg-config \
  libuv1-dev \
  libssl-dev \
  zlib1g-dev \
  libgmp-dev \
  libffi-dev \
  libyaml-dev \
  libreadline-dev \
  git \
  curl \
  wget
```

#### macOS

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install cmake pkg-config libuv openssl zlib
```

### DataStax C++ Driver

The C++ driver is automatically installed by the setup script, but for manual installation:

```bash
# Download and build
cd /tmp
wget https://github.com/datastax/cpp-driver/archive/2.16.2.tar.gz
tar -xzf 2.16.2.tar.gz
cd cpp-driver-2.16.2

mkdir build && cd build
cmake .. \
  -DCASS_BUILD_STATIC=ON \
  -DCASS_BUILD_SHARED=ON \
  -DCASS_USE_STATIC_LIBS=ON \
  -DCASS_USE_ZLIB=ON \
  -DCASS_USE_OPENSSL=ON

make -j$(nproc)
sudo make install
sudo ldconfig  # Linux only
```

## Docker Configuration

### Development Services

Our Docker Compose setup provides:

- **Cassandra Cluster**: 2-node cluster for development
- **Development Container**: Pre-configured Ruby environment
- **Testing Container**: Isolated testing environment
- **Redis**: Optional caching layer
- **Monitoring**: Prometheus and Grafana (optional)

### Service Architecture

```
┌─────────────────┐    ┌─────────────────┐
│  Cassandra-1    │    │  Cassandra-2    │
│  (Seed Node)    │◄──►│  (Replica)      │
│  Port: 9042     │    │  Port: 9043     │
└─────────────────┘    └─────────────────┘
         │                       │
         └───────────┬───────────┘
                     │
         ┌─────────────────┐
         │   Dev Container │
         │   Ruby 3.2      │
         │   All Tools     │
         └─────────────────┘
```

### Starting Services

```bash
# Start core services
docker-compose up -d cassandra-1 cassandra-2

# Start development environment
docker-compose up -d cassandra-cpp-dev

# Start with monitoring (optional)
docker-compose --profile monitoring up -d

# Access development shell
docker exec -it cassandra-cpp-dev bash
```

### Environment Variables

Create environment files for different contexts:

**.env.development**
```bash
CASSANDRA_HOSTS=cassandra-1,cassandra-2
CASSANDRA_PORT=9042
CASSANDRA_KEYSPACE=cassandra_cpp_development
RUBY_ENV=development
LOG_LEVEL=debug
```

**.env.test**
```bash
CASSANDRA_HOSTS=cassandra-1,cassandra-2
CASSANDRA_PORT=9042
CASSANDRA_KEYSPACE=cassandra_cpp_test
RUBY_ENV=test
LOG_LEVEL=warn
```

## Development Workflow

### Git Flow Strategy

We follow a modified Git Flow with these branches:

- **main**: Production-ready code
- **develop**: Integration branch for features
- **feature/***: Feature development
- **release/***: Release preparation
- **hotfix/***: Critical fixes

### Branch Naming Convention

```
feature/add-connection-pooling
bugfix/fix-memory-leak
hotfix/security-patch-cve-2024-1234
release/v2.1.0
```

### Commit Convention

We use [Conventional Commits](https://conventionalcommits.org/):

```
feat: add batch operation support
fix: resolve connection timeout issue
docs: update installation guide
style: format code with rubocop
refactor: extract connection pool logic
test: add integration tests for clustering
chore: update dependencies
```

### Pull Request Workflow

1. Create feature branch from `develop`
2. Implement changes with tests
3. Ensure CI passes (tests, linting, type checking)
4. Request code review
5. Merge after approval

### Code Review Guidelines

- **Functionality**: Does it work as intended?
- **Design**: Follows SOLID principles?
- **Tests**: Adequate coverage?
- **Performance**: No regressions?
- **Security**: No vulnerabilities?
- **Documentation**: Updated as needed?

## Code Quality Tools

### Static Type Checking with Sorbet

```bash
# Initialize Sorbet
bundle exec srb init

# Generate RBI files
bundle exec tapioca gems

# Type check
bundle exec srb tc

# Fix type errors
bundle exec srb tc --suggest-typed
```

### Code Formatting with RuboCop

```bash
# Check style
bundle exec rubocop

# Auto-fix
bundle exec rubocop -a

# Check specific files
bundle exec rubocop lib/cassandra_cpp/connection.rb
```

### Documentation with YARD

```bash
# Generate documentation
bundle exec yard doc

# View documentation
open doc/index.html

# Check coverage
bundle exec yard stats --list-undoc
```

### Git Hooks with Overcommit

```bash
# Install hooks
bundle exec overcommit --install

# Sign configuration
bundle exec overcommit --sign

# Run manually
bundle exec overcommit --run
```

## Testing Strategy

### Test Structure

```
spec/
├── unit/                 # Unit tests
│   ├── cassandra_cpp/
│   └── support/
├── integration/          # Integration tests
│   ├── cluster_spec.rb
│   └── connection_spec.rb
├── performance/          # Performance tests
│   └── benchmarks/
├── fixtures/             # Test data
└── support/             # Test helpers
    ├── spec_helper.rb
    ├── cassandra_helper.rb
    └── factory_helpers.rb
```

### Running Tests

```bash
# All tests
bundle exec rspec

# Unit tests only
bundle exec rspec spec/unit

# Integration tests
bundle exec rspec spec/integration

# Performance tests
bundle exec rspec spec/performance

# With coverage
COVERAGE=true bundle exec rspec

# Parallel execution
bundle exec parallel_rspec spec/
```

### Test Categories

#### Unit Tests
- Fast execution (< 1ms per test)
- No external dependencies
- Mock external services
- Focus on single responsibility

#### Integration Tests
- Test component interactions
- Use real Cassandra instance
- Verify end-to-end workflows
- Database fixture management

#### Performance Tests
- Benchmark critical paths
- Memory usage monitoring
- Regression detection
- Load testing scenarios

### Test Utilities

```ruby
# spec/support/spec_helper.rb
require 'simplecov'
require 'factory_bot'
require 'faker'
require 'timecop'
require 'webmock'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/vendor/'
  
  add_group 'Models', 'lib/cassandra_cpp/model'
  add_group 'Connection', 'lib/cassandra_cpp/connection'
  add_group 'Query', 'lib/cassandra_cpp/query'
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include CassandraHelpers
  
  config.before(:suite) do
    DatabaseCleaner.strategy = :truncation
  end
  
  config.before(:each) do
    DatabaseCleaner.start
  end
  
  config.after(:each) do
    DatabaseCleaner.clean
  end
end
```

## SOLID Principles Implementation

### Single Responsibility Principle (SRP)

Each class should have one reason to change:

```ruby
# Good: Focused responsibility
class ConnectionPool
  def initialize(config)
    @config = config
    @connections = []
  end
  
  def checkout
    # Connection checkout logic only
  end
  
  def checkin(connection)
    # Connection checkin logic only
  end
end

class QueryBuilder
  def initialize
    @conditions = []
    @projections = []
  end
  
  def where(condition)
    # Query building logic only
  end
  
  def select(*columns)
    # Projection logic only
  end
end
```

### Open/Closed Principle (OCP)

Open for extension, closed for modification:

```ruby
# Base retry policy
class RetryPolicy
  def should_retry?(error, attempt)
    raise NotImplementedError
  end
end

# Extended policies
class ExponentialBackoffRetry < RetryPolicy
  def should_retry?(error, attempt)
    return false if attempt > 3
    sleep(2 ** attempt)
    true
  end
end

class LinearBackoffRetry < RetryPolicy
  def should_retry?(error, attempt)
    return false if attempt > 5
    sleep(attempt * 0.5)
    true
  end
end
```

### Liskov Substitution Principle (LSP)

Subclasses should be substitutable for their base classes:

```ruby
class DataType
  def serialize(value)
    raise NotImplementedError
  end
  
  def deserialize(value)
    raise NotImplementedError
  end
end

class IntegerType < DataType
  def serialize(value)
    return nil if value.nil?
    Integer(value)
  end
  
  def deserialize(value)
    return nil if value.nil?
    value.to_i
  end
end

class UuidType < DataType
  def serialize(value)
    return nil if value.nil?
    CassandraCpp::Uuid.new(value)
  end
  
  def deserialize(value)
    return nil if value.nil?
    value.to_s
  end
end

# Both can be used interchangeably
def process_data(data_type, value)
  serialized = data_type.serialize(value)
  data_type.deserialize(serialized)
end
```

### Interface Segregation Principle (ISP)

Clients shouldn't depend on interfaces they don't use:

```ruby
# Focused interfaces
module Queryable
  def where(conditions)
    raise NotImplementedError
  end
  
  def limit(count)
    raise NotImplementedError
  end
end

module Executable
  def execute
    raise NotImplementedError
  end
end

module Batchable
  def add_to_batch(batch)
    raise NotImplementedError
  end
end

# Implement only needed interfaces
class SelectQuery
  include Queryable
  include Executable
  # Doesn't include Batchable - read operations aren't batchable
end

class InsertStatement
  include Executable
  include Batchable
  # Doesn't include Queryable - insert doesn't support where/limit
end
```

### Dependency Inversion Principle (DIP)

Depend on abstractions, not concretions:

```ruby
# Abstract logger interface
class Logger
  def log(level, message)
    raise NotImplementedError
  end
end

# Concrete implementations
class ConsoleLogger < Logger
  def log(level, message)
    puts "[#{level}] #{message}"
  end
end

class FileLogger < Logger
  def initialize(file_path)
    @file_path = file_path
  end
  
  def log(level, message)
    File.open(@file_path, 'a') do |f|
      f.puts "[#{Time.now}] [#{level}] #{message}"
    end
  end
end

# Dependency injection
class Connection
  def initialize(config, logger: ConsoleLogger.new)
    @config = config
    @logger = logger  # Depends on abstraction
  end
  
  private
  
  def log_error(message)
    @logger.log('ERROR', message)
  end
end
```

## Performance Considerations

### Memory Management

```ruby
# Use object pooling for frequently created objects
class UuidPool
  def initialize(size = 100)
    @pool = Queue.new
    size.times { @pool << CassandraCpp::Uuid.new }
  end
  
  def checkout
    @pool.pop(non_block: true)
  rescue ThreadError
    CassandraCpp::Uuid.new
  end
  
  def checkin(uuid)
    @pool.push(uuid.reset) if @pool.size < 100
  end
end

# Minimize object allocation in hot paths
class QueryCache
  def initialize
    @cache = {}
    @mutex = Mutex.new
  end
  
  def fetch(key)
    # Use frozen strings to reduce allocation
    frozen_key = key.freeze
    
    @mutex.synchronize do
      @cache[frozen_key] ||= yield
    end
  end
end
```

### Benchmarking Infrastructure

```ruby
# spec/performance/benchmarks/connection_benchmark.rb
require 'benchmark/ips'
require 'benchmark/memory'

RSpec.describe 'Connection Performance' do
  let(:cluster) { CassandraCpp::Cluster.build(hosts: ['localhost']) }
  
  it 'benchmarks connection creation' do
    Benchmark.ips do |x|
      x.report('connection creation') do
        cluster.connect
      end
      
      x.compare!
    end
  end
  
  it 'measures memory usage' do
    Benchmark.memory do |x|
      x.report('query execution') do
        100.times do
          cluster.execute('SELECT * FROM system.local')
        end
      end
    end
  end
end
```

### Profiling Tools Integration

```ruby
# Profile with ruby-prof
def profile_query_execution
  RubyProf.start
  
  1000.times do
    cluster.execute('SELECT * FROM users WHERE id = ?', uuid)
  end
  
  result = RubyProf.stop
  
  # Print a graph profile to text
  printer = RubyProf::GraphPrinter.new(result)
  printer.print(STDOUT, {})
end

# Profile with stackprof
StackProf.run(mode: :cpu, out: 'tmp/stackprof.dump') do
  1000.times do
    User.find(random_uuid)
  end
end
```

## Troubleshooting

### Common Issues

#### Docker Issues

**Issue**: Cassandra containers fail to start
```bash
# Check logs
docker-compose logs cassandra-1

# Check resources
docker system df
docker system prune  # if needed

# Restart with clean state
docker-compose down -v
docker-compose up -d
```

**Issue**: Port conflicts
```bash
# Check port usage
lsof -i :9042

# Use different ports in docker-compose.yml
ports:
  - "9142:9042"  # Changed from 9042
```

#### Ruby Environment Issues

**Issue**: Gem compilation failures
```bash
# Ensure development headers are installed
sudo apt-get install ruby-dev

# Clear gem cache
rm -rf vendor/bundle
bundle install
```

**Issue**: Native extension compilation
```bash
# Check compiler
gcc --version
cmake --version

# Reinstall DataStax driver
sudo make uninstall
./bin/setup  # Reinstall everything
```

#### Performance Issues

**Issue**: Slow test execution
```bash
# Run tests in parallel
bundle exec parallel_rspec spec/

# Profile slow tests
PROFILE=true bundle exec rspec spec/slow_spec.rb
```

**Issue**: Memory leaks
```bash
# Use memory profiler
MEMORY_PROFILE=true bundle exec rspec

# Check with valgrind (development container)
valgrind --tool=memcheck ruby your_script.rb
```

### Debug Mode

Enable debug logging:

```bash
# Environment variable
DEBUG=1 bundle exec rspec

# In code
CassandraCpp.logger.level = :debug

# Docker container with debug
docker-compose run --rm \
  -e DEBUG=1 \
  cassandra-cpp-dev \
  bundle exec rspec
```

### Getting Help

1. **Check Documentation**: Start with this guide and API docs
2. **Search Issues**: Look through GitHub issues
3. **Enable Debug Logging**: Get detailed error information
4. **Minimal Reproduction**: Create a simple test case
5. **Community Support**: Reach out on Slack or Stack Overflow

### Development Best Practices

1. **Write Tests First**: TDD approach for new features
2. **Small Commits**: Atomic changes with clear messages
3. **Code Review**: Every change should be reviewed
4. **Performance Awareness**: Profile before optimizing
5. **Documentation**: Keep docs up to date
6. **Security**: Never commit secrets or credentials

## Next Steps

After completing the setup:

1. **Explore the Codebase**: Start with `lib/cassandra_cpp.rb`
2. **Run the Test Suite**: `bundle exec rspec`
3. **Try the Examples**: Check out `examples/` directory
4. **Build Something**: Create a simple application
5. **Contribute**: Fix a bug or add a feature

For more detailed information, see:
- [Contributing Guide](10_contributing.md)
- [Performance Tuning](07_performance.md)
- [Troubleshooting](09_troubleshooting.md)