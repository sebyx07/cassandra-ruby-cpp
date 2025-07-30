#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/cassandra_cpp'

# Basic connectivity test example
def main
  puts "Cassandra-CPP Basic Connection Test"
  puts "=" * 40
  
  # Configuration
  config = {
    hosts: ['localhost'],
    port: 9042,
    keyspace: 'cassandra_cpp_development'
  }
  
  begin
    # Create cluster connection
    puts "Connecting to Cassandra cluster..."
    cluster = CassandraCpp::Cluster.build(config)
    
    # Test basic connectivity
    puts "Testing basic connectivity..."
    session = cluster.connect
    
    puts "✅ Connected successfully!"
    puts "  Keyspace: #{session.keyspace || 'none'}"
    
    # Test basic query
    puts "\nTesting basic queries..."
    result = session.execute("SELECT cluster_name, release_version FROM system.local")
    
    if result.empty?
      puts "⚠️  No results returned"
    else
      row = result.first
      puts "✅ Query successful!"
      puts "  Cluster: #{row['cluster_name']}"
      puts "  Version: #{row['release_version']}"
    end
    
    # Test creating a simple table
    puts "\nTesting table operations..."
    session.execute("DROP TABLE IF EXISTS test_poc")
    session.execute(<<~CQL)
      CREATE TABLE IF NOT EXISTS test_poc (
        id UUID PRIMARY KEY,
        name TEXT,
        value INT,
        created_at TIMESTAMP
      )
    CQL
    puts "✅ Table created successfully"
    
    # Test inserting data
    test_id = CassandraCpp::Uuid.generate
    session.execute(
      "INSERT INTO test_poc (id, name, value, created_at) VALUES (?, ?, ?, ?)",
      test_id,
      'test_record',
      42,
      Time.now
    )
    puts "✅ Data inserted successfully"
    
    # Test querying data
    result = session.execute("SELECT * FROM test_poc WHERE id = ?", test_id)
    if result.empty?
      puts "❌ No data found"
    else
      row = result.first
      puts "✅ Data retrieved successfully:"
      puts "  ID: #{row['id']}"
      puts "  Name: #{row['name']}"
      puts "  Value: #{row['value']}"
      puts "  Created: #{row['created_at']}"
    end
    
    # Clean up
    session.execute("DROP TABLE test_poc")
    puts "✅ Cleanup completed"
    
    session.close
    cluster.close
    
    puts "\n🎉 All tests passed! Cassandra-CPP POC is working."
    
  rescue CassandraCpp::ConnectionError => e
    puts "❌ Connection failed: #{e.message}"
    puts "\nTroubleshooting:"
    puts "1. Make sure Cassandra is running (docker-compose up -d)"
    puts "2. Check that the keyspace exists"
    puts "3. Verify host and port configuration"
    exit 1
    
  rescue CassandraCpp::QueryError => e
    puts "❌ Query failed: #{e.message}"
    exit 1
    
  rescue StandardError => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME