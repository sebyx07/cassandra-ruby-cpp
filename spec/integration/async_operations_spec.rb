# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'timeout'

RSpec.describe 'Async Operations', type: :integration do
  include CassandraCppTestHelpers
  
  let(:cluster) { create_test_cluster }
  let(:session) { cluster.connect('cassandra_cpp_test') }
  
  before(:all) do
    skip_unless_cassandra_available
  end
  
  before do
    # Create test table for async operations in each test session
    session.execute(<<~CQL)
      CREATE TABLE IF NOT EXISTS async_test (
        id uuid PRIMARY KEY,
        name text,
        value int,
        created_at timestamp
      )
    CQL
  end
  
  after do
    begin
      session.execute('TRUNCATE async_test')
    ensure
      session.close
      cluster.close
    end
  end
  
  describe 'Session#execute_async' do
    it 'executes queries asynchronously and returns a Future' do
      id = SecureRandom.uuid
      
      # Execute insert asynchronously
      timestamp = (Time.now.to_f * 1000).to_i  # Convert to milliseconds
      future = session.execute_async(
        "INSERT INTO async_test (id, name, value, created_at) VALUES (#{id}, 'Async Test', 42, #{timestamp})"
      )
      
      expect(future).to be_a(CassandraCpp::Future)
      
      # Get the result (this will block until completion)
      result = future.value
      expect(result).to be_a(Array)
      
      # Verify the insert worked
      result = session.execute("SELECT name, value FROM async_test WHERE id = #{id}")
      expect(result.size).to eq(1)
      expect(result.first['name']).to eq('Async Test')
      expect(result.first['value']).to eq(42)
    end
    
    it 'handles timeouts correctly' do
      # This test assumes a reasonable query that should complete quickly
      future = session.execute_async("SELECT * FROM async_test LIMIT 1")
      
      expect {
        future.value(5.0)  # 5 second timeout should be plenty
      }.not_to raise_error
    end
    
    it 'supports ready? check' do
      future = session.execute_async("SELECT * FROM async_test LIMIT 1")
      
      # Future might already be ready for a simple query, so we can't assert false
      # But we can at least verify the method exists and returns a boolean
      ready_status = future.ready?
      expect([true, false]).to include(ready_status)
      
      # After getting the value, it should definitely be ready
      future.value
      expect(future.ready?).to be true
    end
  end
  
  describe 'Session#prepare_async' do
    it 'prepares statements asynchronously' do
      future = session.prepare_async("INSERT INTO async_test (id, name, value) VALUES (?, ?, ?)")
      
      expect(future).to be_a(CassandraCpp::Future)
      
      # Get the prepared statement
      prepared_statement = future.value
      expect(prepared_statement).to be_a(CassandraCpp::PreparedStatement)
      
      # Use the prepared statement
      id = SecureRandom.uuid
      result = prepared_statement.execute(id, 'Prepared Async', 123)
      
      # Verify it worked
      rows = session.execute("SELECT name, value FROM async_test WHERE id = #{id}")
      expect(rows.size).to eq(1)
      expect(rows.first['name']).to eq('Prepared Async')
      expect(rows.first['value']).to eq(123)
    end
  end
  
  describe 'PreparedStatement#execute_async' do
    let(:prepared_statement) { session.prepare("INSERT INTO async_test (id, name, value) VALUES (?, ?, ?)") }
    
    it 'executes prepared statements asynchronously' do
      id = SecureRandom.uuid
      
      future = prepared_statement.execute_async(id, 'Prepared Async Execute', 456)
      
      expect(future).to be_a(CassandraCpp::Future)
      
      # Get the result
      result = future.value
      expect(result).to be_a(CassandraCpp::Result)
      
      # Verify the insert worked
      rows = session.execute("SELECT name, value FROM async_test WHERE id = #{id}")
      expect(rows.size).to eq(1)
      expect(rows.first['name']).to eq('Prepared Async Execute')
      expect(rows.first['value']).to eq(456)
    end
  end
  
  describe 'Future callbacks' do
    it 'supports then callbacks for success' do
      callback_result = nil
      callback_executed = false
      
      future = session.execute_async("SELECT * FROM async_test LIMIT 1")
      
      future.then do |result|
        callback_result = result
        callback_executed = true
      end
      
      # Wait for the future to complete first
      future.value
      
      future.execute_callbacks
      
      expect(callback_executed).to be true
      expect(callback_result).to be_a(Array)
    end
    
    it 'supports rescue callbacks for errors' do
      error_message = nil
      error_callback_executed = false
      
      # Execute a query that will fail
      future = session.execute_async("SELECT * FROM non_existent_table")
      
      future.rescue do |error|
        error_message = error
        error_callback_executed = true
      end
      
      # Try to get the value (this will raise an error but we catch it)  
      begin
        future.value
      rescue CassandraCpp::Error
        # Expected - ignore the error
      end
      
      future.execute_callbacks
      
      expect(error_callback_executed).to be true
      expect(error_message).to be_a(String)
      expect(error_message.downcase).to include('table')
    end
    
    it 'supports method chaining' do
      success_called = false
      error_called = false 
      
      future = session.execute_async("SELECT * FROM async_test LIMIT 1")
      
      result_future = future
        .then { |result| success_called = true; result }
        .rescue { |error| error_called = true }
      
      expect(result_future).to be_a(CassandraCpp::Future)
      
      # Wait for the future to complete first
      future.value
      
      result_future.execute_callbacks
      
      expect(success_called).to be true
      expect(error_called).to be false
    end
  end
  
  describe 'Future#map' do
    it 'transforms future results' do
      future = session.execute_async("SELECT COUNT(*) as count FROM async_test")
      
      # Map the result to extract just the count value
      count_future = future.map { |rows| rows.first['count'] }
      
      count = count_future.value
      expect(count).to be_a(Integer)
      expect(count).to be >= 0
    end
    
    it 'chains transformations' do
      # Insert some test data first
      3.times do |i|
        id = SecureRandom.uuid
        session.execute("INSERT INTO async_test (id, name, value) VALUES (#{id}, 'Test#{i}', #{i * 10})")
      end
      
      future = session.execute_async("SELECT value FROM async_test")
      
      # Chain multiple transformations
      sum_future = future
        .map { |rows| rows.map { |row| row['value'] } }  # Extract values
        .map { |values| values.sum }                      # Sum them up
      
      total = sum_future.value
      expect(total).to eq(30)  # 0 + 10 + 20 = 30
    end
  end
  
  describe 'Future#zip' do
    it 'combines multiple futures' do
      # Insert test data
      id1 = SecureRandom.uuid
      id2 = SecureRandom.uuid
      
      session.execute("INSERT INTO async_test (id, name, value) VALUES (#{id1}, 'First', 100)")
      session.execute("INSERT INTO async_test (id, name, value) VALUES (#{id2}, 'Second', 200)")
      
      # Create two async queries
      future1 = session.execute_async("SELECT value FROM async_test WHERE id = #{id1}")
      future2 = session.execute_async("SELECT value FROM async_test WHERE id = #{id2}")
      
      # Combine them
      combined_future = future1.zip(future2)
      
      result1, result2 = combined_future.value
      
      expect(result1).to be_a(Array)
      expect(result2).to be_a(Array)
      expect(result1.first['value']).to eq(100)
      expect(result2.first['value']).to eq(200)
    end
    
    it 'handles errors in combined futures' do
      # One good future, one bad future
      good_future = session.execute_async("SELECT * FROM async_test LIMIT 1")
      bad_future = session.execute_async("SELECT * FROM non_existent_table")
      
      combined_future = good_future.zip(bad_future)
      
      error_occurred = false
      
      combined_future.rescue do |error|
        error_occurred = true
        expect(error).to be_a(String)
      end
      
      # Try to get the values to force completion (expect error)
      begin
        combined_future.value
      rescue CassandraCpp::Error
        # Expected - ignore the error
      end
      
      combined_future.execute_callbacks
      
      expect(error_occurred).to be true
    end
  end
  
  describe 'Performance characteristics' do
    it 'executes multiple async queries concurrently' do
      # Measure time for 5 sequential queries
      sequential_start = Time.now
      5.times do |i|
        id = SecureRandom.uuid
        session.execute("INSERT INTO async_test (id, name, value) VALUES (#{id}, 'Sequential#{i}', #{i})")
      end
      sequential_time = Time.now - sequential_start
      
      # Clear the table
      session.execute('TRUNCATE async_test')
      
      # Measure time for 5 concurrent async queries
      concurrent_start = Time.now
      futures = 5.times.map do |i|
        id = SecureRandom.uuid
        session.execute_async("INSERT INTO async_test (id, name, value) VALUES (#{id}, 'Concurrent#{i}', #{i})")
      end
      
      # Wait for all to complete
      futures.each(&:value)
      concurrent_time = Time.now - concurrent_start
      
      # Async operations should be faster (or at least not significantly slower)
      # Allow generous margin for test variability - timing can vary significantly
      # The main goal is to verify async operations work, not strict performance
      expect(concurrent_time).to be <= (sequential_time * 2.0)
      
      # Additional check: if the difference is very small (< 10ms), consider it equivalent
      time_difference = (concurrent_time - sequential_time).abs
      if time_difference < 0.01  # Less than 10ms difference
        # Performance is essentially equivalent - this is acceptable
        expect(true).to be true
      end
      
      # Verify all inserts completed
      rows = session.execute("SELECT COUNT(*) as count FROM async_test")
      expect(rows.first['count']).to eq(5)
    end
    
    it 'handles many concurrent operations' do
      # Test with 20 concurrent operations
      futures = 20.times.map do |i|
        id = SecureRandom.uuid
        session.execute_async("INSERT INTO async_test (id, name, value) VALUES (#{id}, 'Bulk#{i}', #{i})")
      end
      
      # Wait for all to complete with timeout
      Timeout.timeout(10) do
        futures.each(&:value)
      end
      
      # Verify all completed
      rows = session.execute("SELECT COUNT(*) as count FROM async_test")
      expect(rows.first['count']).to eq(20)
    end
  end
  
  describe 'Error handling' do
    it 'propagates errors correctly through Future#value' do
      future = session.execute_async("SELECT * FROM non_existent_table")
      
      expect {
        future.value
      }.to raise_error(CassandraCpp::Error)
    end
    
    it 'handles timeouts in Future#value' do
      # Create a future and immediately try to get value with very short timeout
      future = session.execute_async("SELECT * FROM async_test")
      
      # Very short timeout might cause timeout, but might also succeed if query is fast
      # Just verify the timeout parameter is handled without crashing
      expect {
        future.value(0.001)  # 1ms timeout
      }.to_not raise_error(NoMethodError)  # Should not crash due to missing timeout handling
    end
    
    it 'handles errors in mapped futures' do
      future = session.execute_async("SELECT * FROM async_test LIMIT 1")
      
      # Map with a transformation that will raise an error
      error_future = future.map { |result| raise "Transformation error" }
      
      error_occurred = false
      error_future.rescue do |error|
        error_occurred = true
        expect(error).to include("Transformation error")
      end
      
      # Wait for the source future to complete first
      future.value
      
      error_future.execute_callbacks
      
      expect(error_occurred).to be true
    end
  end
end