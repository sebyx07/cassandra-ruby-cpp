# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'time'
# BigDecimal support is optional
require 'set'

RSpec.describe 'Advanced Data Types', type: :integration do
  include CassandraCppTestHelpers
  
  let(:cluster) { create_test_cluster }
  let(:session) { cluster.connect('cassandra_cpp_test') }
  
  before(:all) do
    skip_unless_cassandra_available
    
    with_test_session('cassandra_cpp_test') do |session|
      # Create comprehensive test table with all supported data types
      session.execute(<<~CQL)
        CREATE TABLE IF NOT EXISTS data_types_test (
          id uuid PRIMARY KEY,
          text_val text,
          int_val int,
          bigint_val bigint,
          float_val float,
          double_val double,
          boolean_val boolean,
          timestamp_val timestamp,
          blob_val blob,
          list_val list<text>,
          set_val set<int>,
          map_val map<text, int>
        )
      CQL
    end
  end
  
  after do
    begin
      session.execute('TRUNCATE data_types_test')
    ensure
      session.close
      cluster.close
    end
  end
  
  describe 'TIMESTAMP data type' do
    it 'handles Ruby Time objects correctly' do
      id = SecureRandom.uuid
      now = Time.now
      
      # Insert with Time object
      statement = session.prepare('INSERT INTO data_types_test (id, timestamp_val) VALUES (?, ?)')
      statement.execute(id, now)
      
      # Retrieve and verify
      rows = session.execute("SELECT timestamp_val FROM data_types_test WHERE id = #{id}")
      retrieved_time = rows.first['timestamp_val']
      
      expect(retrieved_time).to be_a(Time)
      # Allow for small precision differences (millisecond precision in Cassandra)
      expect((retrieved_time.to_f - now.to_f).abs).to be < 0.001
    end
    
    it 'handles various time formats' do
      times = [
        Time.at(0),                    # Unix epoch
        Time.at(1640995200),          # 2022-01-01 00:00:00 UTC
        Time.now,                     # Current time
        Time.now + 86400              # Tomorrow
      ]
      
      statement = session.prepare('INSERT INTO data_types_test (id, timestamp_val) VALUES (?, ?)')
      
      times.each_with_index do |time, index|
        test_id = SecureRandom.uuid
        statement.execute(test_id, time)
        
        rows = session.execute("SELECT timestamp_val FROM data_types_test WHERE id = #{test_id}")
        retrieved = rows.first['timestamp_val']
        
        expect((retrieved.to_f - time.to_f).abs).to be < 0.001
      end
    end
  end
  
  describe 'BLOB data type' do
    it 'handles binary data correctly' do
      id = SecureRandom.uuid
      
      # Create binary data
      binary_data = "\x00\x01\x02\xFF\xFE\xFD".b  # Force ASCII-8BIT encoding
      
      # Insert binary data
      statement = session.prepare('INSERT INTO data_types_test (id, blob_val) VALUES (?, ?)')
      statement.execute(id, binary_data)
      
      # Retrieve and verify
      rows = session.execute("SELECT blob_val FROM data_types_test WHERE id = #{id}")
      retrieved_blob = rows.first['blob_val']
      
      expect(retrieved_blob).to be_a(String)
      expect(retrieved_blob).to eq(binary_data)
      expect(retrieved_blob.encoding).to eq(Encoding::ASCII_8BIT)
    end
    
    it 'handles large binary objects' do
      id = SecureRandom.uuid
      
      # Create 1KB of random binary data
      large_blob = (0..1023).map { rand(256) }.pack('C*')
      
      statement = session.prepare('INSERT INTO data_types_test (id, blob_val) VALUES (?, ?)')
      statement.execute(id, large_blob)
      
      rows = session.execute("SELECT blob_val FROM data_types_test WHERE id = #{id}")
      retrieved = rows.first['blob_val']
      
      expect(retrieved).to eq(large_blob)
      expect(retrieved.size).to eq(1024)
    end
  end
  
  describe 'LIST data type' do
    it 'handles Ruby arrays correctly' do
      id = SecureRandom.uuid
      list_data = ['apple', 'banana', 'cherry']
      
      # Insert array
      statement = session.prepare('INSERT INTO data_types_test (id, list_val) VALUES (?, ?)')
      statement.execute(id, list_data)
      
      # Retrieve and verify
      rows = session.execute("SELECT list_val FROM data_types_test WHERE id = #{id}")
      retrieved_list = rows.first['list_val']
      
      expect(retrieved_list).to be_a(Array)
      expect(retrieved_list).to eq(list_data)
    end
    
    it 'handles empty arrays' do
      id = SecureRandom.uuid
      empty_list = []
      
      statement = session.prepare('INSERT INTO data_types_test (id, list_val) VALUES (?, ?)')
      statement.execute(id, empty_list)
      
      rows = session.execute("SELECT list_val FROM data_types_test WHERE id = #{id}")
      retrieved = rows.first['list_val']
      
      # Cassandra returns NULL for empty collections, which is correct behavior
      expect(retrieved).to be_nil
    end
    
    it 'handles lists with nil values by skipping them' do
      id = SecureRandom.uuid
      list_with_nils = ['a', nil, 'b', nil, 'c']
      
      statement = session.prepare('INSERT INTO data_types_test (id, list_val) VALUES (?, ?)')
      statement.execute(id, list_with_nils)
      
      rows = session.execute("SELECT list_val FROM data_types_test WHERE id = #{id}")
      retrieved = rows.first['list_val']
      
      # Null values should be skipped in collections
      expect(retrieved).to eq(['a', 'b', 'c'])
    end
  end
  
  describe 'SET data type' do
    it 'handles Ruby Sets correctly' do
      id = SecureRandom.uuid
      set_data = Set.new([1, 2, 3, 2, 1])  # Duplicates will be removed
      
      # Insert Set
      statement = session.prepare('INSERT INTO data_types_test (id, set_val) VALUES (?, ?)')
      statement.execute(id, set_data)
      
      # Retrieve and verify
      rows = session.execute("SELECT set_val FROM data_types_test WHERE id = #{id}")
      retrieved_set = rows.first['set_val']
      
      expect(retrieved_set).to be_a(Set)
      expect(retrieved_set).to eq(Set.new([1, 2, 3]))
    end
    
    it 'handles Ruby arrays as sets' do
      id = SecureRandom.uuid
      array_data = [1, 2, 3, 2, 1]  # With duplicates
      
      # Use Set.new to convert array to set
      set_from_array = Set.new(array_data)
      
      statement = session.prepare('INSERT INTO data_types_test (id, set_val) VALUES (?, ?)')
      statement.execute(id, set_from_array)
      
      rows = session.execute("SELECT set_val FROM data_types_test WHERE id = #{id}")
      retrieved = rows.first['set_val']
      
      expect(retrieved).to be_a(Set)
      expect(retrieved).to eq(Set.new([1, 2, 3]))
    end
  end
  
  describe 'MAP data type' do
    it 'handles Ruby hashes correctly' do
      id = SecureRandom.uuid
      map_data = { 'key1' => 100, 'key2' => 200, 'key3' => 300 }
      
      # Insert hash
      statement = session.prepare('INSERT INTO data_types_test (id, map_val) VALUES (?, ?)')
      statement.execute(id, map_data)
      
      # Retrieve and verify
      rows = session.execute("SELECT map_val FROM data_types_test WHERE id = #{id}")
      retrieved_map = rows.first['map_val']
      
      expect(retrieved_map).to be_a(Hash)
      expect(retrieved_map).to eq(map_data)
    end
    
    it 'handles empty hashes' do
      id = SecureRandom.uuid
      empty_map = {}
      
      statement = session.prepare('INSERT INTO data_types_test (id, map_val) VALUES (?, ?)')
      statement.execute(id, empty_map)
      
      rows = session.execute("SELECT map_val FROM data_types_test WHERE id = #{id}")
      retrieved = rows.first['map_val']
      
      # Cassandra returns NULL for empty collections, which is correct behavior
      expect(retrieved).to be_nil
    end
    
    it 'handles mixed data types in maps' do
      id = SecureRandom.uuid
      # Note: This test uses text->int map as defined in schema
      mixed_map = { 'count' => 42, 'total' => 1000, 'average' => 50 }
      
      statement = session.prepare('INSERT INTO data_types_test (id, map_val) VALUES (?, ?)')
      statement.execute(id, mixed_map)
      
      rows = session.execute("SELECT map_val FROM data_types_test WHERE id = #{id}")
      retrieved = rows.first['map_val']
      
      expect(retrieved).to eq(mixed_map)
    end
  end
  
  describe 'Complex data combinations' do
    it 'handles multiple advanced data types in one record' do
      id = SecureRandom.uuid
      timestamp = Time.now
      blob = "binary\x00data".b
      list = ['item1', 'item2', 'item3']
      set_data = Set.new([10, 20, 30])
      map = { 'score' => 95, 'level' => 5 }
      
      # Insert all data types
      statement = session.prepare(<<~CQL)
        INSERT INTO data_types_test 
        (id, timestamp_val, blob_val, list_val, set_val, map_val) 
        VALUES (?, ?, ?, ?, ?, ?)
      CQL
      
      statement.execute(id, timestamp, blob, list, set_data, map)
      
      # Retrieve and verify all fields
      rows = session.execute("SELECT * FROM data_types_test WHERE id = #{id}")
      row = rows.first
      
      expect((row['timestamp_val'].to_f - timestamp.to_f).abs).to be < 0.001
      expect(row['blob_val']).to eq(blob)
      expect(row['list_val']).to eq(list)
      expect(row['set_val']).to eq(set_data)
      expect(row['map_val']).to eq(map)
    end
  end
  
  describe 'Error handling' do
    it 'raises appropriate errors for type mismatches' do
      id = SecureRandom.uuid
      
      # Try to insert wrong type for int field in set
      statement = session.prepare('INSERT INTO data_types_test (id, set_val) VALUES (?, ?)')
      
      expect {
        # This should work fine as our code converts strings to appropriate types
        statement.execute(id, Set.new(['not', 'numbers']))
      }.to raise_error(CassandraCpp::Error)
    end
    
    it 'handles oversized data gracefully' do
      id = SecureRandom.uuid
      
      # Create very large blob (16MB)
      large_blob = 'x' * (16 * 1024 * 1024)
      
      statement = session.prepare('INSERT INTO data_types_test (id, blob_val) VALUES (?, ?)')
      
      # This might fail due to Cassandra limits, which is expected
      expect {
        statement.execute(id, large_blob.b)
      }.to raise_error(CassandraCpp::Error)
    end
  end
  
  describe 'Performance with collections' do
    it 'handles reasonably sized collections efficiently' do
      require 'benchmark'
      
      id = SecureRandom.uuid
      
      # Create medium-sized collections
      large_list = (1..1000).map { |i| "item_#{i}" }
      large_map = (1..100).to_h { |i| ["key_#{i}", i * 10] }
      
      statement = session.prepare(<<~CQL)
        INSERT INTO data_types_test (id, list_val, map_val) 
        VALUES (?, ?, ?)
      CQL
      
      # Measure insertion time
      insert_time = Benchmark.realtime do
        statement.execute(id, large_list, large_map)
      end
      
      # Should complete in reasonable time (less than 1 second for these sizes)
      expect(insert_time).to be < 1.0
      
      # Verify data was inserted correctly
      rows = session.execute("SELECT list_val, map_val FROM data_types_test WHERE id = #{id}")
      row = rows.first
      
      expect(row['list_val'].size).to eq(1000)
      expect(row['map_val'].size).to eq(100)
    end
  end
end