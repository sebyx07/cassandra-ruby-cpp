# Cassandra-CPP Development Roadmap

This document outlines the complete roadmap for implementing a full-featured Cassandra ORM with native C++ performance.

## 🎯 Current Status

✅ **COMPLETED** - Phase 1: Core Infrastructure
- [x] Native C++ extension with DataStax driver integration
- [x] Basic connection management and query execution
- [x] Memory management and error handling
- [x] Comprehensive test suite (35 tests passing)
- [x] Docker development environment
- [x] Documentation and examples

**Next Phase**: Advanced Driver Features + ORM Foundation

---

## 📋 Phase 2: Advanced Driver Features (Priority: HIGH)

### 2.1 Prepared Statements & Parameter Binding
**Status**: ✅ COMPLETED | **Effort**: 2-3 weeks

#### Native Extension Updates
- [x] ✅ Add `CassStatement` wrapper to C++ extension
- [x] ✅ Implement parameter binding for different data types
- [x] ✅ Add statement caching mechanism (basic implementation in Session)
- [x] ✅ Add batch statement support with fluent interface
- [x] ✅ Environment-aware configuration (CASSANDRA_HOSTS, CASSANDRA_PORT)
- [ ] Support for named parameters (`?` and `:name` syntax)

```cpp
// ext/cassandra_cpp/cassandra_cpp.cpp additions
static VALUE statement_new(VALUE klass, VALUE query);
static VALUE statement_bind(VALUE self, VALUE index, VALUE value);
static VALUE statement_execute(VALUE self);
```

#### Ruby Interface
- [x] ✅ Create `CassandraCpp::PreparedStatement` class
- [x] ✅ Add automatic parameter type detection (UUID, basic types)
- [x] ✅ Implement statement preparation caching
- [x] ✅ Add batch statement support with fluent interface

```ruby
# lib/cassandra_cpp/prepared_statement.rb
class PreparedStatement
  def bind(*args)
  def bind_hash(hash)
  def execute
end
```

#### Tests Required
- [x] ✅ Parameter binding for all data types
- [x] ✅ Statement caching behavior
- [x] ✅ Performance benchmarks vs simple queries
- [x] ✅ Batch statement functionality
- [x] ✅ Environment-based configuration tests
- [x] ✅ Docker container testing support

### 2.2 Async Operations & Futures
**Status**: Not Started | **Effort**: 3-4 weeks

#### Native Extension Updates
- [ ] Implement `CassFuture` wrapper
- [ ] Add async query execution methods
- [ ] Implement callback mechanisms
- [ ] Add promise/future pattern support

```cpp
// Async operations in C++
static VALUE session_execute_async(VALUE self, VALUE query);
static VALUE future_get(VALUE self, VALUE timeout);
static VALUE future_on_success(VALUE self);
```

#### Ruby Interface
- [ ] Create `CassandraCpp::Future` class
- [ ] Implement callback-based async operations
- [ ] Add promise chaining support
- [ ] Integrate with Ruby's async patterns

```ruby
# lib/cassandra_cpp/future.rb
class Future
  def then(&block)
  def rescue(&block)
  def value(timeout = nil)
end
```

### 2.3 Connection Pooling & Load Balancing
**Status**: Not Started | **Effort**: 2-3 weeks

#### Native Extension Updates
- [ ] Implement connection pool management
- [ ] Add load balancing policies
- [ ] Implement retry policies
- [ ] Add connection health monitoring

#### Ruby Interface
- [ ] Create `CassandraCpp::ConnectionPool` class
- [ ] Implement pool configuration options
- [ ] Add monitoring and metrics
- [ ] Health check mechanisms

### 2.4 Advanced Data Types
**Status**: ✅ COMPLETED | **Effort**: 2-3 weeks

Current support: TEXT, INT, BIGINT, BOOLEAN, UUID, FLOAT, DOUBLE, NULL, TIMESTAMP, BLOB, LIST, SET, MAP, TUPLE

#### Implemented Data Types
- [x] ✅ **TIMESTAMP** - Ruby Time objects with millisecond precision
- [x] ✅ **DECIMAL** - Basic BigDecimal support (string representation)
- [x] ✅ **FLOAT/DOUBLE** - Full precision handling
- [x] ✅ **BLOB** - Binary data support with automatic encoding detection
- [x] ✅ **LIST** - Ruby Array type support with nested type conversion
- [x] ✅ **SET** - Ruby Set type support with automatic deduplication  
- [x] ✅ **MAP** - Ruby Hash support with nested key-value type conversion
- [x] ✅ **TUPLE** - Tuple type support (mapped to Ruby Arrays)
- [ ] **UDT** - User Defined Types (deferred to future release)

#### Implementation Completed
- [x] ✅ Add C++ type conversion functions (bind_ruby_value_to_statement, convert_cass_value_to_ruby)
- [x] ✅ Implement Ruby type mapping with automatic detection (T_DATA, T_OBJECT, etc.)
- [x] ✅ Add serialization/deserialization for all collection types
- [x] ✅ Create comprehensive test coverage (16 advanced data type tests)
- [x] ✅ Binary data handling with null-byte support
- [x] ✅ Collection iterator memory management
- [x] ✅ Proper empty collection handling (returns nil as per Cassandra spec)

---

## 🏗️ Phase 3: ORM Foundation (Priority: HIGH)

### 3.1 Schema Management & Migrations
**Status**: Not Started | **Effort**: 3-4 weeks

#### Core Components
- [ ] Create `CassandraCpp::Schema` module
- [ ] Implement table introspection
- [ ] Add migration framework
- [ ] Schema version management

```ruby
# lib/cassandra_cpp/schema/
├── migration.rb          # Migration framework
├── table.rb             # Table definition DSL
├── column.rb            # Column type definitions
└── introspector.rb      # Schema introspection
```

#### Migration System
```ruby
class CreateUsersTable < CassandraCpp::Migration
  def up
    create_table :users do |t|
      t.uuid :id, primary_key: true
      t.text :name, null: false
      t.text :email, unique: true
      t.timestamp :created_at, default: 'now()'
      t.map :metadata, key_type: :text, value_type: :text
    end
  end
end
```

#### Tasks
- [ ] Design migration DSL
- [ ] Implement table creation/modification
- [ ] Add index management
- [ ] Schema validation and rollback
- [ ] Integration with existing schema tools

### 3.2 Model Layer (ActiveRecord-Style ORM)
**Status**: Not Started | **Effort**: 4-6 weeks

#### Base Model Implementation
- [ ] Create `CassandraCpp::Model` base class
- [ ] Implement attribute definition and typing
- [ ] Add validation framework
- [ ] Implement callbacks (before_save, after_create, etc.)

```ruby
# lib/cassandra_cpp/model.rb
class Model
  include ActiveModel::Validations
  include ActiveModel::Callbacks
  
  def self.table_name
  def self.primary_key
  def self.column(name, type, options = {})
end
```

#### Example Usage
```ruby
class User < CassandraCpp::Model
  table_name 'users'
  
  column :id, :uuid, primary_key: true, default: -> { SecureRandom.uuid }
  column :name, :text, null: false
  column :email, :text, unique: true
  column :age, :int
  column :created_at, :timestamp, default: -> { Time.now }
  column :metadata, :map, key_type: :text, value_type: :text
  
  validates :name, presence: true, length: { minimum: 2 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :age, numericality: { greater_than: 0, less_than: 120 }
  
  before_save :normalize_email
  after_create :send_welcome_email
  
  private
  
  def normalize_email
    self.email = email.downcase.strip
  end
end
```

#### Implementation Tasks
- [ ] **Attribute System**
  - [ ] Type coercion and validation
  - [ ] Default value handling
  - [ ] Dirty tracking (ActiveModel::Dirty)
  - [ ] Serialization/deserialization

- [ ] **Persistence Methods**
  - [ ] `save`, `create`, `update`, `destroy`
  - [ ] Batch operations
  - [ ] Upsert functionality
  - [ ] Optimistic locking

- [ ] **Validation Framework**
  - [ ] Integration with ActiveModel::Validations
  - [ ] Custom Cassandra-specific validators
  - [ ] Async validation support

- [ ] **Callback System**
  - [ ] before/after/around callbacks
  - [ ] Conditional callbacks
  - [ ] Callback chains and inheritance

### 3.3 Query Builder & Finder Methods
**Status**: Not Started | **Effort**: 4-5 weeks

#### Query Builder Implementation
```ruby
# lib/cassandra_cpp/query_builder.rb
class QueryBuilder
  def select(*columns)
  def where(conditions)
  def limit(count)
  def allow_filtering
  def order_by(column, direction = :asc)
end
```

#### Finder Methods
```ruby
class User < CassandraCpp::Model
  # Class methods
  def self.find(id)
  def self.find_by(attributes)
  def self.where(conditions)
  def self.all
  def self.first
  def self.last
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :recent, -> { where('created_at > ?', 1.week.ago) }
end
```

#### Usage Examples
```ruby
# Simple finders
user = User.find('123e4567-e89b-12d3-a456-426614174000')
users = User.where(active: true).limit(10)

# Complex queries
User.where('age > ? AND age < ?', 18, 65)
    .where(active: true)
    .allow_filtering
    .order_by(:created_at, :desc)
    .limit(20)

# Using scopes
User.active.recent.limit(5)
```

#### Implementation Tasks
- [ ] **Query Builder Core**
  - [ ] WHERE clause building
  - [ ] SELECT clause handling
  - [ ] LIMIT and ordering
  - [ ] ALLOW FILTERING support

- [ ] **CQL Generation**
  - [ ] Safe parameter binding
  - [ ] Query optimization
  - [ ] Index usage hints
  - [ ] Prepared statement caching

- [ ] **Result Processing**
  - [ ] Lazy loading of results
  - [ ] Pagination support
  - [ ] Result caching
  - [ ] Memory-efficient iteration

### 3.4 Associations & Relationships
**Status**: Not Started | **Effort**: 5-6 weeks

Note: Cassandra relationships are different from traditional RDBMS - they're typically modeled through denormalization and materialized views.

#### Association Types
```ruby
class User < CassandraCpp::Model
  # One-to-many via denormalization
  has_many :posts, foreign_key: :user_id, dependent: :destroy
  
  # Many-to-many via join table
  has_and_belongs_to_many :groups, through: :user_groups
  
  # Embedded documents (using JSON/MAP columns)
  embeds_many :addresses
  embeds_one :profile
end

class Post < CassandraCpp::Model
  belongs_to :user, foreign_key: :user_id
  
  # Counter columns
  counter :view_count
  counter :like_count
end
```

#### Implementation Tasks
- [ ] **Association Definitions**
  - [ ] has_many/belongs_to/has_one relationships
  - [ ] has_and_belongs_to_many through join tables
  - [ ] Embedded document support
  - [ ] Counter column associations

- [ ] **Query Generation**
  - [ ] Automatic foreign key handling
  - [ ] Eager loading strategies
  - [ ] N+1 query prevention
  - [ ] Batch loading optimization

- [ ] **Data Consistency**
  - [ ] Referential integrity checks
  - [ ] Cascade operations
  - [ ] Atomic batch operations
  - [ ] Eventually consistent strategies

---

## 🚀 Phase 4: Production Features (Priority: MEDIUM)

### 4.1 Advanced Configuration & SSL
**Status**: Not Started | **Effort**: 2-3 weeks

#### SSL/TLS Support
- [ ] Client certificate authentication
- [ ] Server certificate validation
- [ ] SSL context configuration
- [ ] Encrypted connection handling

#### Authentication Methods
- [ ] Username/password authentication
- [ ] LDAP integration
- [ ] SASL authentication
- [ ] Token-based authentication

### 4.2 Monitoring & Metrics
**Status**: Not Started | **Effort**: 2-3 weeks

#### Metrics Collection
- [ ] Query performance metrics
- [ ] Connection pool statistics
- [ ] Error rate monitoring
- [ ] Memory usage tracking

#### Integration Support
- [ ] Prometheus metrics export
- [ ] StatsD integration
- [ ] Custom metrics callbacks
- [ ] APM tool integration

### 4.3 Logging & Debugging
**Status**: Not Started | **Effort**: 1-2 weeks

#### Enhanced Logging
- [ ] Structured logging support
- [ ] Query logging with timing
- [ ] Connection event logging
- [ ] Error context preservation

#### Development Tools
- [ ] Query explain functionality
- [ ] Schema diff tools
- [ ] Performance profiling
- [ ] Development console

---

## 🧪 Testing & Quality Assurance

### Testing Requirements (Per Phase)
- [ ] **Unit Tests**: 90%+ coverage for all new code
- [ ] **Integration Tests**: Full feature testing with real Cassandra
- [ ] **Performance Tests**: Benchmarking against pure Ruby implementations
- [ ] **Memory Tests**: Leak detection and usage profiling
- [ ] **Stress Tests**: High concurrency and load testing

### Performance Benchmarks
Target performance metrics for fully implemented ORM:

| Operation | Current | Target | Notes |
|-----------|---------|--------|-------|
| Simple Query | ~0.7ms | ~0.5ms | With prepared statements |
| Model.find | N/A | ~1ms | Including object instantiation |
| Bulk Insert | N/A | 10,000/sec | Batch operations |
| Complex Query | N/A | ~5ms | With joins and filters |
| Memory Usage | Baseline | -50% | vs pure Ruby ORM |

---

## 📦 Release Schedule

### Version 1.0.0 - Core ORM (Target: Q2 2025)
- ✅ Native extension foundation
- ✅ Basic connection management
- [ ] Prepared statements and async operations
- [ ] Advanced data types
- [ ] Basic model layer
- [ ] Query builder
- [ ] Schema management

### Version 1.1.0 - Advanced Features (Target: Q3 2025)
- [ ] Associations and relationships
- [ ] Advanced configuration
- [ ] Monitoring and metrics
- [ ] Production hardening

### Version 1.2.0 - Production Polish (Target: Q4 2025)
- [ ] Performance optimizations
- [ ] Security hardening
- [ ] Documentation completion
- [ ] Community tooling

---

## 🤝 Contributing Guidelines

### Development Workflow
1. Pick a task from this TODO list
2. Create feature branch: `feature/task-name`
3. Implement with tests (TDD approach)
4. Update documentation
5. Submit PR with benchmarks

### Technical Standards
- **Test Coverage**: Minimum 90% for new code
- **Performance**: No regression in benchmarks
- **Memory**: No memory leaks detected
- **Documentation**: All public APIs documented
- **Examples**: Working examples for new features

### Priority Guidelines
- **HIGH**: Core functionality required for v1.0
- **MEDIUM**: Important features for production use
- **LOW**: Nice-to-have features for complete ORM

---

## 📊 Progress Tracking

**Overall Progress**: 70% Complete (Infrastructure + Prepared Statements + Batch Support + Environment Config + Advanced Data Types + Pure Native Driver)

### Phase Completion Status
- ✅ **Phase 1**: Core Infrastructure (100%)
- 🔄 **Phase 2**: Advanced Driver Features (90% - Prepared Statements ✅, Batch Support ✅, Environment Config ✅, Advanced Data Types ✅)
- ⏳ **Phase 3**: ORM Foundation (0%)  
- ⏳ **Phase 4**: Production Features (0%)

### Next Sprint Priority
1. ✅ ~~Prepared statements implementation~~ COMPLETED
2. ✅ ~~Batch statement support~~ COMPLETED
3. Additional data types (TIMESTAMP, DECIMAL, BLOB, collections)
4. Schema management foundation
5. Basic model layer

---

This roadmap represents approximately **8-12 months** of development work to achieve a production-ready Cassandra ORM with native C++ performance. The modular approach allows for incremental releases and community contributions at each phase.