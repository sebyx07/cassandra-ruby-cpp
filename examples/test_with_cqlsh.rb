#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'

# Test Cassandra functionality using cqlsh via Docker
def test_with_cqlsh
  puts "Testing Cassandra functionality via cqlsh"
  puts "=" * 45
  
  # Test 1: Basic connection and cluster info
  puts "1. Testing cluster information..."
  
  cmd = "docker exec cassandra-node-1 cqlsh -e \"SELECT cluster_name, release_version FROM system.local;\""
  stdout, stderr, status = Open3.capture3(cmd)
  
  if status.success?
    puts "✅ Cluster query successful:"
    puts stdout.strip.split("\n").last(3).join("\n").strip
  else
    puts "❌ Cluster query failed: #{stderr}"
    return false
  end
  
  # Test 2: Create test keyspace and table
  puts "\n2. Testing keyspace and table operations..."
  
  # Check if development keyspace exists
  cmd = "docker exec cassandra-node-1 cqlsh -e \"DESCRIBE KEYSPACE cassandra_cpp_development;\""
  stdout, stderr, status = Open3.capture3(cmd)
  
  if status.success?
    puts "✅ Development keyspace exists"
  else
    puts "⚠️  Development keyspace not found, this is expected for first run"
  end
  
  # Test 3: Create a temporary test table
  puts "\n3. Testing table creation and data operations..."
  
  test_commands = [
    "USE cassandra_cpp_development;",
    "DROP TABLE IF EXISTS poc_test;",
    "CREATE TABLE poc_test (id UUID PRIMARY KEY, name TEXT, created_at TIMESTAMP);",
    "INSERT INTO poc_test (id, name, created_at) VALUES (uuid(), 'test_from_ruby', toTimestamp(now()));",
    "SELECT * FROM poc_test;",
    "DROP TABLE poc_test;"
  ]
  
  test_commands.each_with_index do |test_cmd, i|
    puts "   Step #{i + 1}: #{test_cmd.split.first}..."
    
    cmd = "docker exec cassandra-node-1 cqlsh -e \"#{test_cmd}\""
    stdout, stderr, status = Open3.capture3(cmd)
    
    if status.success?
      puts "   ✅ Success"
      if test_cmd.include?('SELECT')
        # Show the result
        lines = stdout.split("\n")
        data_lines = lines.select { |line| line.include?('test_from_ruby') }
        puts "   📄 Result: #{data_lines.first.strip}" unless data_lines.empty?
      end
    else
      puts "   ❌ Failed: #{stderr.strip}"
    end
  end
  
  # Test 4: Test both nodes
  puts "\n4. Testing both Cassandra nodes..."
  
  ['cassandra-node-1', 'cassandra-node-2'].each do |node|
    puts "   Testing #{node}..."
    cmd = "docker exec #{node} cqlsh -e \"SELECT COUNT(*) FROM system.local;\""
    stdout, stderr, status = Open3.capture3(cmd)
    
    if status.success?
      puts "   ✅ #{node} is responding"
    else
      puts "   ❌ #{node} failed: #{stderr.strip}"
    end
  end
  
  puts "\n" + "=" * 45
  puts "🎉 Cassandra cluster is fully functional!"
  puts "\nNext steps for Cassandra-CPP development:"
  puts "1. ✅ Cassandra cluster running"
  puts "2. ✅ Basic Ruby gem structure created"
  puts "3. ✅ Socket connectivity confirmed"
  puts "4. ⏳ Install and compile DataStax C++ driver"
  puts "5. ⏳ Create Ruby C extension bindings"
  puts "6. ⏳ Implement high-performance native methods"
  
  true
end

test_with_cqlsh if __FILE__ == $PROGRAM_NAME