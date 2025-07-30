# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

RSpec.describe 'Prepared Statements', type: :integration do
  include CassandraCppTestHelpers
  
  let(:cluster) { create_test_cluster }
  let(:session) { cluster.connect('cassandra_cpp_test') }
  
  before(:all) do
    skip_unless_cassandra_available
    
    # Ensure test table exists
    with_test_session('cassandra_cpp_test') do |session|
      session.execute(<<~CQL)
        CREATE TABLE IF NOT EXISTS prepared_test (
          id uuid PRIMARY KEY,
          name text,
          age int,
          active boolean,
          score double,
          created_at timestamp
        )
      CQL
    end
  end
  
  after do
    begin
      session.execute('TRUNCATE prepared_test')
    ensure
      session.close
      cluster.close
    end
  end
  
  describe '#prepare' do
    it 'prepares a simple insert statement' do
      statement = session.prepare('INSERT INTO prepared_test (id, name) VALUES (?, ?)')
      expect(statement).to be_a(CassandraCpp::PreparedStatement)
      expect(statement.query).to eq('INSERT INTO prepared_test (id, name) VALUES (?, ?)')
    end
    
    it 'caches prepared statements' do
      query = 'INSERT INTO prepared_test (id, name) VALUES (?, ?)'
      statement1 = session.prepare(query)
      statement2 = session.prepare(query)
      expect(statement1).to be(statement2)
    end
    
    it 'counts parameters correctly' do
      statement = session.prepare('INSERT INTO prepared_test (id, name, age) VALUES (?, ?, ?)')
      expect(statement.param_count).to eq(3)
      expect(statement.has_params?).to be(true)
    end
    
    it 'handles queries without parameters' do
      statement = session.prepare('SELECT * FROM prepared_test')
      expect(statement.param_count).to eq(0)
      expect(statement.has_params?).to be(false)
    end
  end
  
  describe '#execute' do
    context 'with INSERT statements' do
      it 'executes with string parameters' do
        statement = session.prepare('INSERT INTO prepared_test (id, name) VALUES (?, ?)')
        id = SecureRandom.uuid
        statement.execute(id, 'John Doe')
        
        # Verify the insert
        rows = session.execute("SELECT * FROM prepared_test WHERE id = #{id}")
        expect(rows.count).to eq(1)
        expect(rows.first['name']).to eq('John Doe')
      end
      
      it 'executes with various data types' do
        statement = session.prepare(<<~CQL)
          INSERT INTO prepared_test (id, name, age, active, score)
          VALUES (?, ?, ?, ?, ?)
        CQL
        
        id = SecureRandom.uuid
        statement.execute(id, 'Jane Smith', 30, true, 95.5)
        
        # Verify all fields
        rows = session.execute("SELECT * FROM prepared_test WHERE id = #{id}")
        row = rows.first
        expect(row['name']).to eq('Jane Smith')
        expect(row['age']).to eq(30)
        expect(row['active']).to eq(true)
        expect(row['score']).to eq(95.5)
      end
      
      it 'handles nil values' do
        statement = session.prepare('INSERT INTO prepared_test (id, name, age) VALUES (?, ?, ?)')
        id = SecureRandom.uuid
        statement.execute(id, 'No Age', nil)

        rows = session.execute("SELECT * FROM prepared_test WHERE id = #{id}")
        expect(rows.first['age']).to be_nil
      end
    end
    
    context 'with SELECT statements' do
      before do
        # Insert test data
        3.times do |i|
          session.execute(<<~CQL)
            INSERT INTO prepared_test (id, name, age)
            VALUES (#{SecureRandom.uuid}, 'User #{i}', #{20 + i})
          CQL
        end
      end
      
      it 'executes parameterized SELECT' do
        statement = session.prepare('SELECT * FROM prepared_test WHERE age > ? ALLOW FILTERING')
        result = statement.execute(21)
        
        expect(result.count).to eq(1)
        expect(result.first['name']).to eq('User 2')
      end
      
      it 'returns empty result set when no matches' do
        statement = session.prepare('SELECT * FROM prepared_test WHERE age > ? ALLOW FILTERING')
        result = statement.execute(100)
        
        expect(result.count).to eq(0)
      end
    end
    
    context 'with UPDATE statements' do
      let(:id) { SecureRandom.uuid }
      
      before do
        session.execute(<<~CQL)
          INSERT INTO prepared_test (id, name, age)
          VALUES (#{id}, 'Original Name', 25)
        CQL
      end
      
      it 'executes parameterized UPDATE' do
        statement = session.prepare('UPDATE prepared_test SET name = ?, age = ? WHERE id = ?')
        statement.execute('Updated Name', 30, id)
        
        rows = session.execute("SELECT * FROM prepared_test WHERE id = #{id}")
        row = rows.first
        expect(row['name']).to eq('Updated Name')
        expect(row['age']).to eq(30)
      end
    end
    
    context 'with DELETE statements' do
      let(:id) { SecureRandom.uuid }
      
      before do
        session.execute(<<~CQL)
          INSERT INTO prepared_test (id, name, age)
          VALUES (#{id}, 'To Delete', 25)
        CQL
      end
      
      it 'executes parameterized DELETE' do
        statement = session.prepare('DELETE FROM prepared_test WHERE id = ?')
        statement.execute(id)
        
        rows = session.execute("SELECT * FROM prepared_test WHERE id = #{id}")
        expect(rows.count).to eq(0)
      end
    end
    
    context 'error handling' do
      it 'raises error when parameter count mismatch' do
        statement = session.prepare('INSERT INTO prepared_test (id, name) VALUES (?, ?)')
        
        expect {
          statement.execute(SecureRandom.uuid) # Missing one parameter
        }.to raise_error(ArgumentError, /Wrong number of parameters/)
        
        expect {
          statement.execute(SecureRandom.uuid, 'Name', 'Extra') # Too many parameters
        }.to raise_error(ArgumentError, /Wrong number of parameters/)
      end
      
      it 'raises error for invalid parameter types' do
        statement = session.prepare('INSERT INTO prepared_test (id, age) VALUES (?, ?)')
        
        expect {
          statement.execute(SecureRandom.uuid, 'not a number')
        }.to raise_error(CassandraCpp::Error)
      end
    end
  end
  
  describe 'performance' do
    it 'executes prepared statements faster than regular queries' do
      require 'benchmark'
      
      # Prepare statement
      prepared = session.prepare('INSERT INTO prepared_test (id, name, age) VALUES (?, ?, ?)')
      
      # Measure prepared statement execution
      prepared_time = Benchmark.realtime do
        100.times do
          prepared.execute(SecureRandom.uuid, 'Test User', rand(100))
        end
      end
      
      # Measure regular query execution
      regular_time = Benchmark.realtime do
        100.times do
          id = SecureRandom.uuid
          name = 'Test User'
          age = rand(100)
          session.execute("INSERT INTO prepared_test (id, name, age) VALUES (#{id}, '#{name}', #{age})")
        end
      end
      
      # Prepared statements should be faster or at least comparable
      # In test environments, the difference might be smaller
      expect(prepared_time).to be <= regular_time
    end
  end
  
  describe 'concurrent execution' do
    it 'handles concurrent executions safely' do
      statement = session.prepare('INSERT INTO prepared_test (id, name, age) VALUES (?, ?, ?)')
      
      threads = 10.times.map do |i|
        Thread.new do
          5.times do |j|
            statement.execute(SecureRandom.uuid, "Thread #{i} User #{j}", i * 10 + j)
          end
        end
      end
      
      threads.each(&:join)
      
      # Verify all inserts succeeded
      result = session.execute('SELECT COUNT(*) as count FROM prepared_test')
      expect(result.first['count']).to eq(50)
    end
  end
end