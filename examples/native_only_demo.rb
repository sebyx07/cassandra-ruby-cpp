#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the pure native C++ Cassandra driver
# No Ruby cassandra-driver dependency required!

require_relative '../lib/cassandra_cpp'

begin
  puts "🚀 Cassandra-CPP Native Driver Demo"
  puts "===================================="
  puts
  
  # Check that we're using the native extension
  unless CassandraCpp.native_extension_loaded?
    puts "❌ Native extension not loaded - this demo requires the C++ extension"
    exit 1
  end
  
  puts "✅ Native C++ extension loaded successfully"
  puts
  
  # Connect to Cassandra
  puts "📡 Connecting to Cassandra..."
  cluster = CassandraCpp::Cluster.new(hosts: ['localhost'])
  session = cluster.connect('system')
  
  puts "✅ Connected successfully!"
  puts
  
  # Execute a simple query
  puts "🔍 Executing simple query..."
  result = session.execute("SELECT cluster_name, release_version FROM local")
  
  result.each do |row|
    puts "   Cluster: #{row['cluster_name']}"
    puts "   Version: #{row['release_version']}"
  end
  puts
  
  # Test prepared statements
  puts "⚡ Testing prepared statements..."
  
  # Use a keyspace that should exist
  session = cluster.connect('system')
  
  # Prepare a parameterized query
  prepared = session.prepare("SELECT * FROM local WHERE key = ?")
  
  # Execute with parameters
  result = prepared.execute('local')
  
  puts "   Prepared statement executed successfully!"
  puts "   Result count: #{result.count}"
  puts
  
  # Demonstrate different data types
  puts "🎯 Testing data type binding..."
  
  # Create a test keyspace and table if it doesn't exist
  session.execute("CREATE KEYSPACE IF NOT EXISTS demo WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1}")
  demo_session = cluster.connect('demo')
  
  demo_session.execute(<<~CQL)
    CREATE TABLE IF NOT EXISTS test_types (
      id uuid PRIMARY KEY,
      name text,
      age int,
      active boolean,
      score double
    )
  CQL
  
  # Insert with prepared statement
  insert_stmt = demo_session.prepare(<<~CQL)
    INSERT INTO test_types (id, name, age, active, score)
    VALUES (?, ?, ?, ?, ?)
  CQL
  
  # Generate a UUID
  require 'securerandom'
  test_id = SecureRandom.uuid
  
  # Execute with different data types
  insert_stmt.execute(test_id, "Alice", 30, true, 95.5)
  
  puts "   ✅ Inserted record with UUID: #{test_id}"
  
  # Query it back
  select_stmt = demo_session.prepare("SELECT * FROM test_types WHERE id = ?")
  result = select_stmt.execute(test_id)
  
  if result.count > 0
    row = result.first
    puts "   📋 Retrieved record:"
    puts "      ID: #{row['id']}"
    puts "      Name: #{row['name']}"
    puts "      Age: #{row['age']}"
    puts "      Active: #{row['active']}"
    puts "      Score: #{row['score']}"
  end
  
  puts
  puts "🎉 Demo completed successfully!"
  puts "   This was accomplished using only the native C++ driver"
  puts "   No Ruby cassandra-driver gem required!"

rescue CassandraCpp::ConnectionError => e
  puts "❌ Connection failed: #{e.message}"
  puts "   Make sure Cassandra is running on localhost:9042"
rescue CassandraCpp::Error => e
  puts "❌ Cassandra error: #{e.message}"
rescue StandardError => e
  puts "❌ Unexpected error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  session&.close
  demo_session&.close
end