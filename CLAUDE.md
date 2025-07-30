# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cassandra-CPP is a high-performance Ruby gem providing native C++ bindings to Apache Cassandra through the DataStax C++ driver. The architecture consists of multiple layers:

- **Ruby Layer**: Application-facing API and ORM
- **Ruby Extensions**: Native method bindings 
- **C++ Adapter**: Memory management and type conversion
- **DataStax Driver**: Core Cassandra protocol implementation

Performance is critical - this gem achieves 4-5x faster operations and 75% less memory usage compared to pure Ruby implementations.

## Development Environment Setup

**Initial Setup:**
```bash
./bin/setup  # Automated setup script - handles everything
```

**Manual Docker Commands:**
```bash
# Start Cassandra cluster
docker-compose up -d cassandra-1 cassandra-2

# Development environment 
docker-compose up -d cassandra-cpp-dev

# Access development shell
docker exec -it cassandra-cpp-dev bash

# With monitoring stack
docker-compose --profile monitoring up -d
```

**Environment Variables:**
- Development: Uses `cassandra_cpp_development` keyspace
- Test: Uses `cassandra_cpp_test` keyspace  
- Hosts: `cassandra-1,cassandra-2` in Docker, `localhost` for local

## Core Development Commands

**Testing:**
```bash
# Full test suite
bundle exec rspec

# Unit tests only  
bundle exec rspec spec/unit

# Integration tests (requires Cassandra)
bundle exec rspec spec/integration

# Performance benchmarks
bundle exec rspec spec/performance

# Single test file
bundle exec rspec spec/unit/model_spec.rb

# Specific test
bundle exec rspec spec/unit/model_spec.rb:42

# With coverage
COVERAGE=true bundle exec rspec

# Parallel execution
bundle exec parallel_rspec spec/
```

**Code Quality:**
```bash
# Lint with RuboCop
bundle exec rubocop

# Auto-fix style issues
bundle exec rubocop -a

# Type checking with Sorbet
bundle exec srb tc

# Generate/update RBI files
bundle exec tapioca gems

# Check for secrets in code
ruby scripts/check_secrets.rb
```

**Documentation:**
```bash
# Generate YARD documentation
bundle exec yard doc

# View documentation
open doc/index.html

# Check documentation coverage  
bundle exec yard stats --list-undoc
```

**Git Hooks:**
```bash
# Install/update git hooks
bundle exec overcommit --install
bundle exec overcommit --sign

# Run hooks manually
bundle exec overcommit --run
```

## Architecture Deep Dive

### ORM Layer (ActiveRecord-inspired)
- **Models**: Inherit from `CassandraCpp::Model` 
- **Column Types**: Maps Ruby types to Cassandra CQL types with automatic conversion
- **Validations**: Built-in and custom validators
- **Callbacks**: Lifecycle hooks (before_save, after_create, etc.)
- **Associations**: belongs_to, has_many, has_one with lazy loading
- **Scopes**: Chainable query methods

### Connection Management
- **Cluster**: Top-level connection builder with configuration
- **Connection Pool**: Automatic pooling with health checks
- **Load Balancing**: Token-aware routing with DC awareness  
- **Retry Policies**: Configurable retry strategies
- **Prepared Statements**: Automatic query preparation for performance

### Type System
- **Native Types**: Direct C++ type mapping for performance
- **Custom Types**: Extensible type conversion system (JSON, encrypted, etc.)
- **Collections**: Set, List, Map with proper serialization
- **UDTs**: User-defined types with nested object support

### Query Builder
- **CQL Generation**: Builds optimized CQL from Ruby DSL
- **Batch Operations**: Atomic multi-statement execution
- **Streaming**: Large result set handling with cursors
- **Async Operations**: Non-blocking query execution

## Key Implementation Patterns

**SOLID Principles:**
- Single Responsibility: Each class has focused purpose
- Open/Closed: Strategy patterns for extensibility (retry policies, load balancers)
- Liskov Substitution: All data types implement consistent interfaces
- Interface Segregation: Separate interfaces for Queryable, Executable, Batchable
- Dependency Inversion: Dependency injection for loggers, connection pools

**Performance Considerations:**
- Object pooling for frequently created objects (UUIDs, connections)
- Prepared statement caching at class level
- Minimal object allocation in hot paths
- Native memory management for large datasets

**Error Handling:**  
- Structured exception hierarchy
- Automatic retry with exponential backoff
- Circuit breaker pattern for failing nodes
- Graceful degradation strategies

## Testing Strategy

**Test Structure:**
- `spec/unit/`: Fast tests with mocked dependencies
- `spec/integration/`: End-to-end tests with real Cassandra
- `spec/performance/`: Benchmarks and regression tests
- `spec/support/`: Test helpers and factories

**Test Database:**
- Uses separate `cassandra_cpp_test` keyspace
- DatabaseCleaner with truncation strategy
- Factory pattern for test data creation
- Timecop for time-dependent tests

## Documentation Requirements

**When modifying code, always update relevant documentation:**

1. **API Documentation**: YARD comments for all public methods
2. **User Guides**: Update `docs/` markdown files for feature changes
3. **Examples**: Update code examples in documentation and README
4. **Type Signatures**: Update Sorbet RBI files for type changes
5. **Changelog**: Document breaking changes and new features

**Documentation Structure:**
- `docs/00_overview.md` - High-level overview and architecture
- `docs/04_orm_models.md` - Model definition and usage patterns  
- `docs/05_queries.md` - Query building and execution
- `docs/07_performance.md` - Performance tuning and optimization
- `docs/11_development_setup.md` - Complete development environment guide

## Dependencies and Build

**System Requirements:**
- Ruby 3.2+ (3.0+ supported)
- DataStax C++ driver 2.15+
- CMake, pkg-config for native compilation
- Docker 20.10+ for development environment

**Native Compilation:**
The gem includes C++ extensions that link against the DataStax driver. The `bin/setup` script handles driver installation, but manual compilation requires:

```bash
# Install DataStax C++ driver (handled by setup script)
cd /tmp && wget https://github.com/datastax/cpp-driver/archive/2.16.2.tar.gz
# ... compilation steps in setup script

# Compile Ruby extensions  
bundle exec rake compile
```

**CI/CD Pipeline:**
- Matrix testing across Ruby 3.0-3.3 and Cassandra 3.11-4.1
- Static analysis with RuboCop and Sorbet
- Performance regression detection  
- Multi-platform gem building (Linux, macOS)
- Automated release with semantic versioning