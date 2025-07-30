# Contributing Guide

Welcome to the Cassandra-CPP project! This guide covers everything you need to know to contribute effectively to the project, from setting up your development environment to submitting pull requests.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing](#testing)
- [Performance Testing](#performance-testing)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)
- [Issue Guidelines](#issue-guidelines)
- [Release Process](#release-process)
- [Community Guidelines](#community-guidelines)

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Ruby**: 2.7.0 or higher (3.0+ recommended)
- **Git**: Latest version
- **C++ Compiler**: GCC 4.8+, Clang 3.4+, or MSVC 2015+
- **CMake**: 3.10 or higher
- **DataStax C++ Driver**: 2.15.0 or higher
- **Docker**: For testing across environments (optional but recommended)

### Fork and Clone

```bash
# Fork the repository on GitHub
# https://github.com/your-org/cassandra-cpp/fork

# Clone your fork
git clone https://github.com/YOUR_USERNAME/cassandra-cpp.git
cd cassandra-cpp

# Add upstream remote
git remote add upstream https://github.com/your-org/cassandra-cpp.git

# Verify remotes
git remote -v
```

### Quick Start

```bash
# Install dependencies
bundle install

# Compile native extensions
bundle exec rake compile

# Run tests
bundle exec rake test

# Check code style
bundle exec rubocop

# Start contributing!
```

## Development Setup

### Local Development Environment

```bash
# Install development dependencies
bundle install --with development test

# Setup pre-commit hooks
cp scripts/pre-commit .git/hooks/
chmod +x .git/hooks/pre-commit

# Setup development database (if using Docker)
docker-compose -f docker/development.yml up -d

# Wait for Cassandra to be ready
scripts/wait-for-cassandra.sh

# Setup test keyspaces
bundle exec rake db:setup
```

### IDE Configuration

#### VS Code

Create `.vscode/settings.json`:

```json
{
  "ruby.codeCompletion": "rcodetools",
  "ruby.intellisense": "rubyLocate",
  "ruby.useLanguageServer": true,
  "ruby.format": "rubocop",
  "ruby.lint": {
    "rubocop": true,
    "reek": true
  },
  "files.associations": {
    "Gemfile": "ruby",
    "Rakefile": "ruby",
    "*.gemspec": "ruby"
  },
  "files.exclude": {
    "**/.git": true,
    "**/tmp": true,
    "**/log": true,
    "**/*.so": true,
    "**/*.o": true
  }
}
```

#### RubyMine

1. Open project in RubyMine
2. Configure Ruby SDK: Settings → Languages & Frameworks → Ruby SDK
3. Enable Rubocop: Settings → Editor → Inspections → Ruby → Rubocop
4. Configure test framework: Settings → Languages & Frameworks → Ruby SDK and Gems

### Environment Variables

Create `.env` file for development:

```bash
# Database Configuration
CASSANDRA_HOSTS=127.0.0.1
CASSANDRA_PORT=9042
CASSANDRA_KEYSPACE=cassandra_cpp_development
CASSANDRA_USERNAME=cassandra
CASSANDRA_PASSWORD=cassandra

# Test Configuration
TEST_CASSANDRA_KEYSPACE=cassandra_cpp_test

# Development Settings
LOG_LEVEL=debug
ENABLE_QUERY_LOGGING=true
ENABLE_PERFORMANCE_LOGGING=true

# C++ Driver Settings
CASS_DRIVER_LOG_LEVEL=INFO
```

### Docker Development

```yaml
# docker-compose.development.yml
version: '3.8'
services:
  cassandra:
    image: cassandra:4.0
    container_name: cassandra-cpp-dev
    environment:
      - CASSANDRA_CLUSTER_NAME=dev-cluster
      - CASSANDRA_DC=datacenter1
      - CASSANDRA_RACK=rack1
      - CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch
    ports:
      - "9042:9042"
      - "7000:7000"
    volumes:
      - cassandra-data:/var/lib/cassandra
    healthcheck:
      test: ["CMD-SHELL", "cqlsh -u cassandra -p cassandra -e 'describe keyspaces'"]
      interval: 30s
      timeout: 10s
      retries: 5

  ruby-dev:
    build:
      context: .
      dockerfile: Dockerfile.development
    volumes:
      - .:/app
      - bundle-cache:/usr/local/bundle
    depends_on:
      cassandra:
        condition: service_healthy
    environment:
      - CASSANDRA_HOSTS=cassandra
    command: bash

volumes:
  cassandra-data:
  bundle-cache:
```

## Code Style Guidelines

### Ruby Style

We follow [RuboCop](https://rubocop.org/) with some customizations:

```yaml
# .rubocop.yml
AllCops:
  TargetRubyVersion: 2.7
  NewCops: enable
  Exclude:
    - 'vendor/**/*'
    - 'tmp/**/*'
    - 'log/**/*'
    - 'ext/**/*'  # C extensions

# Customize specific cops
Layout/LineLength:
  Max: 100
  AllowedPatterns: ['\A#']

Style/Documentation:
  Enabled: false  # We use YARD for documentation

Metrics/MethodLength:
  Max: 15
  Exclude:
    - 'spec/**/*'

Metrics/ClassLength:
  Max: 150

Style/FrozenStringLiteralComment:
  Enabled: true
  EnforcedStyle: always
```

### C++ Style

For C++ extension code:

```cpp
// Use 2-space indentation
// Use snake_case for variables and functions
// Use PascalCase for classes
// Always use braces for control structures

class CassandraSession {
 public:
  explicit CassandraSession(const CassConfig* config);
  ~CassandraSession();
  
  CassError execute_query(const std::string& query);
  
 private:
  CassSession* session_;
  Casscluster* cluster_;
  
  void initialize_cluster(const CassConfig* config);
  void cleanup_resources();
};
```

### Naming Conventions

```ruby
# Classes and Modules - PascalCase
class UserRepository
module CassandraCpp::Utilities

# Methods and Variables - snake_case
def find_by_email(email)
  user_records = []

# Constants - SCREAMING_SNAKE_CASE
DEFAULT_TIMEOUT = 5000
MAX_RETRY_ATTEMPTS = 3

# Files - snake_case
user_repository.rb
connection_pool.rb
```

### Code Organization

```ruby
# File structure for classes
class User < CassandraCpp::Model
  # 1. Include/extend statements
  include Validations
  extend ClassMethods
  
  # 2. Constants
  DEFAULT_STATUS = 'active'
  
  # 3. Attribute definitions
  column :id, :uuid, primary_key: true
  column :email, :text
  
  # 4. Validations
  validates :email, presence: true
  
  # 5. Callbacks
  before_save :normalize_email
  
  # 6. Class methods
  def self.find_by_email(email)
    # implementation
  end
  
  # 7. Instance methods
  def full_name
    "#{first_name} #{last_name}"
  end
  
  # 8. Private methods
  private
  
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
end
```

## Testing

### Test Structure

```
spec/
├── support/           # Test helpers and shared examples
├── unit/             # Unit tests
│   ├── models/       # Model tests
│   ├── queries/      # Query tests
│   └── types/        # Type converter tests
├── integration/      # Integration tests
│   ├── connection/   # Connection tests
│   └── performance/  # Performance tests
├── acceptance/       # End-to-end tests
└── fixtures/         # Test data
```

### Writing Tests

#### Unit Tests

```ruby
# spec/unit/models/user_spec.rb
require 'spec_helper'

RSpec.describe User do
  describe '.find_by_email' do
    let(:email) { 'test@example.com' }
    let(:user) { create(:user, email: email) }
    
    it 'finds user by email' do
      result = User.find_by_email(email)
      expect(result).to eq(user)
    end
    
    it 'returns nil for non-existent email' do
      result = User.find_by_email('nonexistent@example.com')
      expect(result).to be_nil
    end
    
    context 'with case variations' do
      it 'finds user regardless of case' do
        result = User.find_by_email(email.upcase)
        expect(result).to eq(user)
      end
    end
  end
  
  describe '#save' do
    let(:user) { build(:user) }
    
    it 'saves valid user' do
      expect { user.save! }.not_to raise_error
      expect(user).to be_persisted
    end
    
    it 'validates required fields' do
      user.email = nil
      expect { user.save! }.to raise_error(CassandraCpp::ValidationError)
    end
  end
end
```

#### Integration Tests

```ruby
# spec/integration/connection_spec.rb
require 'spec_helper'

RSpec.describe 'Connection Management', :integration do
  let(:cluster) do
    CassandraCpp::Cluster.build do |config|
      config.hosts = [ENV.fetch('CASSANDRA_HOSTS', '127.0.0.1')]
      config.keyspace = 'cassandra_cpp_test'
    end
  end
  
  describe 'basic connectivity' do
    it 'connects to cluster' do
      session = cluster.connect
      expect(session).to be_connected
      session.close
    end
    
    it 'executes simple query' do
      session = cluster.connect
      result = session.execute('SELECT key FROM system.local')
      expect(result).not_to be_empty
      session.close
    end
  end
  
  describe 'connection pooling' do
    it 'reuses connections efficiently' do
      sessions = 5.times.map { cluster.connect }
      
      # Should reuse connections from pool
      expect(cluster.active_connections).to be <= 3
      
      sessions.each(&:close)
    end
  end
end
```

#### Performance Tests

```ruby
# spec/performance/query_performance_spec.rb
require 'spec_helper'

RSpec.describe 'Query Performance', :performance do
  let(:user_count) { 1000 }
  
  before do
    # Setup test data
    users_data = user_count.times.map do |i|
      {
        id: CassandraCpp::Uuid.generate,
        email: "user#{i}@example.com",
        name: "User #{i}"
      }
    end
    
    User.batch_insert(users_data)
  end
  
  describe 'bulk operations' do
    it 'performs batch inserts efficiently' do
      new_users = 500.times.map do |i|
        {
          id: CassandraCpp::Uuid.generate,
          email: "newuser#{i}@example.com",
          name: "New User #{i}"
        }
      end
      
      elapsed_time = Benchmark.realtime do
        User.batch_insert(new_users)
      end
      
      # Should complete in under 2 seconds
      expect(elapsed_time).to be < 2.0
      
      # Verify throughput
      throughput = new_users.size / elapsed_time
      expect(throughput).to be > 250  # ops/second
    end
  end
  
  describe 'query optimization' do
    it 'uses prepared statements efficiently' do
      emails = 100.times.map { |i| "user#{i}@example.com" }
      
      # Warm up prepared statement cache
      User.find_by_email(emails.first)
      
      elapsed_time = Benchmark.realtime do
        emails.each { |email| User.find_by_email(email) }
      end
      
      # Should average less than 10ms per query
      avg_time = elapsed_time / emails.size
      expect(avg_time).to be < 0.01
    end
  end
end
```

### Test Helpers

```ruby
# spec/support/database_cleaner.rb
RSpec.configure do |config|
  config.before(:suite) do
    # Setup test keyspace
    DatabaseCleaner.strategy = :truncation
  end
  
  config.before(:each) do
    DatabaseCleaner.start
  end
  
  config.after(:each) do
    DatabaseCleaner.clean
  end
end

# spec/support/factories.rb
FactoryBot.define do
  factory :user do
    id { CassandraCpp::Uuid.generate }
    email { Faker::Internet.email }
    name { Faker::Name.name }
    age { rand(18..80) }
    status { 'active' }
    created_at { Time.now }
  end
  
  factory :admin_user, parent: :user do
    email { 'admin@example.com' }
    roles { ['admin'] }
  end
end

# spec/support/shared_examples.rb
RSpec.shared_examples 'a valid model' do
  it 'has valid factory' do
    expect(build(described_class.name.underscore.to_sym)).to be_valid
  end
  
  it 'requires primary key' do
    subject.id = nil
    expect(subject).not_to be_valid
  end
end
```

### Running Tests

```bash
# All tests
bundle exec rspec

# Specific test types
bundle exec rspec spec/unit
bundle exec rspec spec/integration
bundle exec rspec spec/performance

# Specific files
bundle exec rspec spec/unit/models/user_spec.rb

# With coverage
COVERAGE=true bundle exec rspec

# Parallel execution
bundle exec parallel_rspec spec/

# CI configuration
CI=true COVERAGE=true bundle exec rspec --format progress
```

## Performance Testing

### Benchmarking Framework

```ruby
# lib/cassandra_cpp/benchmarks.rb
module CassandraCpp
  class Benchmarks
    include Benchmark
    
    def self.run_all
      new.run_all
    end
    
    def run_all
      puts "Cassandra-CPP Performance Benchmarks"
      puts "=" * 50
      
      run_connection_benchmarks
      run_query_benchmarks
      run_batch_benchmarks
      run_memory_benchmarks
    end
    
    private
    
    def run_connection_benchmarks
      puts "\nConnection Benchmarks:"
      
      bmbm do |bench|
        bench.report("Connection creation") do
          100.times do
            cluster = CassandraCpp::Cluster.build(hosts: ['127.0.0.1'])
            session = cluster.connect
            session.close
            cluster.close
          end
        end
        
        bench.report("Connection reuse") do
          cluster = CassandraCpp::Cluster.build(hosts: ['127.0.0.1'])
          
          100.times do
            session = cluster.connect
            session.execute("SELECT key FROM system.local")
            session.close
          end
          
          cluster.close
        end
      end
    end
    
    def run_query_benchmarks
      puts "\nQuery Benchmarks:"
      
      # Setup test data
      setup_benchmark_data
      
      bmbm do |bench|
        bench.report("Simple finds (100x)") do
          100.times { User.find(sample_user_id) }
        end
        
        bench.report("Prepared statements (100x)") do
          stmt = User.prepare("SELECT * FROM users WHERE id = ?")
          100.times { User.execute(stmt.bind(sample_user_id)) }
        end
        
        bench.report("Batch finds (100 IDs)") do
          User.find(sample_user_ids)
        end
        
        bench.report("Complex query") do
          User.where(status: 'active').where('age > ?', 25).limit(50).to_a
        end
      end
    end
    
    def run_memory_benchmarks
      puts "\nMemory Benchmarks:"
      
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i
      
      # Test memory usage patterns
      benchmark_memory_usage("Large result set") do
        User.limit(10000).to_a
      end
      
      benchmark_memory_usage("Streaming") do
        User.find_each(batch_size: 1000) { |user| user.email }
      end
      
      memory_after = `ps -o rss= -p #{Process.pid}`.to_i
      puts "Total memory change: #{memory_after - memory_before}KB"
    end
    
    def benchmark_memory_usage(description)
      memory_before = `ps -o rss= -p #{Process.pid}`.to_i
      
      time = Benchmark.realtime { yield }
      
      memory_after = `ps -o rss= -p #{Process.pid}`.to_i
      memory_used = memory_after - memory_before
      
      puts "#{description}:"
      puts "  Time: #{(time * 1000).round(2)}ms"
      puts "  Memory: #{memory_used}KB"
      
      # Force GC and measure again
      GC.start
      memory_after_gc = `ps -o rss= -p #{Process.pid}`.to_i
      memory_retained = memory_after_gc - memory_before
      
      puts "  Retained after GC: #{memory_retained}KB"
    end
  end
end

# Usage
bundle exec ruby -e "require_relative 'lib/cassandra_cpp'; CassandraCpp::Benchmarks.run_all"
```

### CI Performance Testing

```yaml
# .github/workflows/performance.yml
name: Performance Tests

on:
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  performance:
    runs-on: ubuntu-latest
    
    services:
      cassandra:
        image: cassandra:4.0
        ports:
          - 9042:9042
        options: >-
          --health-cmd "cqlsh -u cassandra -p cassandra -e 'describe keyspaces'"
          --health-interval 30s
          --health-timeout 10s
          --health-retries 10
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.0
          bundler-cache: true
      
      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y build-essential cmake libuv1-dev libssl-dev
      
      - name: Install DataStax driver
        run: |
          wget https://github.com/datastax/cpp-driver/archive/2.16.2.tar.gz
          tar xzf 2.16.2.tar.gz
          cd cpp-driver-2.16.2
          mkdir build && cd build
          cmake ..
          make -j$(nproc)
          sudo make install
          sudo ldconfig
      
      - name: Compile extensions
        run: bundle exec rake compile
      
      - name: Setup test database
        run: |
          sleep 30  # Wait for Cassandra
          bundle exec rake db:setup
        env:
          CASSANDRA_HOSTS: localhost
      
      - name: Run performance tests
        run: bundle exec rspec spec/performance --format json --out performance_results.json
      
      - name: Run benchmarks
        run: bundle exec ruby -e "require_relative 'lib/cassandra_cpp'; CassandraCpp::Benchmarks.run_all" > benchmark_results.txt
      
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: performance-results
          path: |
            performance_results.json
            benchmark_results.txt
      
      - name: Performance regression check
        run: |
          # Compare with baseline (implement your logic)
          bundle exec ruby scripts/check_performance_regression.rb
```

## Documentation

### Code Documentation

Use [YARD](https://yardoc.org/) for API documentation:

```ruby
# @!attribute [r] id
#   @return [String] the unique identifier
# @!attribute [rw] email
#   @return [String] the user's email address

# User model for managing user accounts
#
# @example Creating a new user
#   user = User.new(email: 'john@example.com', name: 'John Doe')
#   user.save!
#
# @example Finding a user
#   user = User.find_by_email('john@example.com')
#
# @since 1.0.0
class User < CassandraCpp::Model
  # Finds a user by email address
  #
  # @param email [String] the email to search for
  # @return [User, nil] the user if found, nil otherwise
  # @raise [CassandraCpp::ValidationError] if email format is invalid
  #
  # @example
  #   user = User.find_by_email('john@example.com')
  #   puts user.name if user
  #
  # @since 1.0.0
  def self.find_by_email(email)
    validate_email_format!(email)
    
    result = execute(find_by_email_statement.bind(email))
    result.first
  end
  
  private
  
  # Validates email format
  # @param email [String] email to validate
  # @raise [CassandraCpp::ValidationError] if invalid
  # @api private
  def self.validate_email_format!(email)
    unless email =~ URI::MailTo::EMAIL_REGEXP
      raise CassandraCpp::ValidationError, "Invalid email format: #{email}"
    end
  end
end
```

### Generating Documentation

```bash
# Generate YARD documentation
bundle exec yard doc

# Generate with stats
bundle exec yard stats --list-undoc

# Serve documentation locally
bundle exec yard server

# Generate documentation with coverage
bundle exec yard doc --markup markdown --output-dir docs/api
```

### README Updates

When adding new features, update the README:

```markdown
## New Feature: Async Operations

Cassandra-CPP now supports asynchronous operations for improved performance:

```ruby
# Async query execution
future = User.find_async('user-id')
result = future.value  # blocks until complete

# Multiple async operations
futures = ids.map { |id| User.find_async(id) }
users = CassandraCpp::Future.all(futures).value
```

See [Advanced Features](docs/08_advanced_features.md#asynchronous-operations) for details.
```

## Pull Request Process

### Before Submitting

1. **Update your fork**:
```bash
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

2. **Create feature branch**:
```bash
git checkout -b feature/awesome-new-feature
```

3. **Make your changes**:
```bash
# Write code
# Add tests
# Update documentation
```

4. **Run full test suite**:
```bash
bundle exec rake test:all
bundle exec rubocop --auto-correct
bundle exec yard doc
```

5. **Commit changes**:
```bash
git add .
git commit -m "Add awesome new feature

- Implement async query execution
- Add comprehensive tests
- Update documentation
- Add performance benchmarks

Fixes #123"
```

### Pull Request Template

```markdown
## Description

Brief description of changes and motivation.

## Type of Change

- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Breaking change (fix or feature causing existing functionality to change)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Refactoring

## Testing

- [ ] Added unit tests
- [ ] Added integration tests
- [ ] Added performance tests
- [ ] All existing tests pass
- [ ] Manual testing performed

## Documentation

- [ ] Updated API documentation
- [ ] Updated README
- [ ] Updated relevant guides
- [ ] Added code examples

## Performance Impact

- [ ] No performance impact
- [ ] Performance improvement (include benchmarks)
- [ ] Potential performance regression (justified)

## Checklist

- [ ] Code follows style guidelines
- [ ] Self-review of code completed
- [ ] Added descriptive comments
- [ ] Updated version number (if applicable)
- [ ] Ready for review

## Related Issues

Fixes #123
Closes #456

## Additional Notes

Any additional information or context.
```

### Review Process

1. **Automated checks**: CI runs tests, linting, and benchmarks
2. **Code review**: Maintainers review code quality and design
3. **Performance review**: For performance-sensitive changes
4. **Documentation review**: Ensure docs are complete and accurate
5. **Approval**: At least one maintainer approval required
6. **Merge**: Squash merge with clean commit message

## Issue Guidelines

### Bug Reports

Use the bug report template:

```markdown
## Bug Description

Clear, concise description of the bug.

## To Reproduce

Steps to reproduce:
1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Environment

- Cassandra-CPP version: 
- Ruby version: 
- OS: 
- Cassandra version: 
- DataStax driver version: 

## Additional Context

- Error messages
- Stack traces
- Configuration
- Sample code
```

### Feature Requests

Use the feature request template:

```markdown
## Feature Description

Clear description of the feature you'd like to see.

## Use Case

Describe the problem this feature would solve.

## Proposed Solution

Describe how you envision the feature working.

## Alternatives Considered

Other solutions you've considered.

## Additional Context

Examples, mockups, related issues, etc.
```

### Performance Issues

```markdown
## Performance Issue

Description of the performance problem.

## Current Performance

- Operation: 
- Current timing: 
- Expected timing: 
- Test environment: 

## Reproduction

Code to reproduce the performance issue.

## Profiling Data

Include any profiling or benchmark data.

## Suggested Optimizations

Ideas for improvement (if any).
```

## Release Process

### Version Numbers

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, backwards compatible

### Release Checklist

1. **Update version**:
```ruby
# lib/cassandra_cpp/version.rb
module CassandraCpp
  VERSION = "2.1.0"
end
```

2. **Update CHANGELOG**:
```markdown
## [2.1.0] - 2023-12-01

### Added
- Async query execution support
- New performance monitoring features
- Connection health checking

### Changed
- Improved error handling in connection pool
- Updated DataStax driver to 2.16.2

### Fixed
- Memory leak in batch operations
- SSL certificate validation issues

### Deprecated
- Old sync-only query methods (will be removed in 3.0.0)
```

3. **Run full test suite**:
```bash
bundle exec rake test:all
bundle exec rake benchmark:all
```

4. **Create release PR**:
```bash
git checkout -b release/v2.1.0
git add .
git commit -m "Release v2.1.0"
git push origin release/v2.1.0
```

5. **After merge, tag release**:
```bash
git checkout main
git pull upstream main
git tag -a v2.1.0 -m "Version 2.1.0"
git push upstream v2.1.0
```

6. **Build and push gem**:
```bash
gem build cassandra-cpp.gemspec
gem push cassandra-cpp-2.1.0.gem
```

7. **Create GitHub release**:
- Go to GitHub releases
- Create new release from tag
- Copy CHANGELOG entry as description
- Attach gem file

## Community Guidelines

### Code of Conduct

We follow the [Contributor Covenant](https://www.contributor-covenant.org/):

- **Be respectful**: Treat everyone with respect and kindness
- **Be inclusive**: Welcome people of all backgrounds and identities
- **Be collaborative**: Work together constructively
- **Be patient**: Remember that everyone is learning

### Communication Channels

- **GitHub Issues**: Bug reports, feature requests
- **GitHub Discussions**: Questions, ideas, general discussion
- **Slack**: Real-time chat and support
- **Stack Overflow**: Tag questions with `cassandra-cpp`

### Getting Help

Before asking for help:

1. Check existing documentation
2. Search closed issues
3. Review troubleshooting guide
4. Prepare minimal reproduction case

When asking for help:

1. Provide clear problem description
2. Include environment details
3. Share relevant code and errors
4. Describe what you've tried

### Recognition

Contributors are recognized in:

- **CONTRIBUTORS.md**: All contributors listed
- **Release notes**: Major contributors mentioned
- **GitHub**: Contributions visible in commit history
- **Gem metadata**: Maintainers and contributors credited

## Development Workflow

### Daily Development

```bash
# Start of day
git checkout main
git pull upstream main

# Create feature branch
git checkout -b feature/my-feature

# Development cycle
# - Write code
# - Run tests: bundle exec rspec
# - Check style: bundle exec rubocop
# - Commit changes

# Before pushing
bundle exec rake test:all
git push -u origin feature/my-feature

# Create PR
gh pr create --title "Add my feature" --body "Description"
```

### Debugging

```ruby
# Add debug logging
CassandraCpp.logger.level = Logger::DEBUG

# Use debugger
require 'debug'
debugger  # Ruby 3.1+

# Or pry
require 'pry'
binding.pry
```

### Common Tasks

```bash
# Compile native extensions
bundle exec rake compile

# Run specific tests
bundle exec rspec spec/unit/models/
bundle exec rspec spec/integration/

# Generate documentation
bundle exec yard doc

# Check test coverage
COVERAGE=true bundle exec rspec

# Profile performance
bundle exec ruby -e "require_relative 'lib/cassandra_cpp'; CassandraCpp::Benchmarks.run_all"

# Check for security vulnerabilities
bundle audit

# Update dependencies
bundle update
```

Thank you for contributing to Cassandra-CPP! Your contributions help make this project better for everyone. If you have questions about contributing, please don't hesitate to ask in our community channels.