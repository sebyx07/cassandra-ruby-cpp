#!/usr/bin/env ruby
# frozen_string_literal: true

require 'socket'
require 'timeout'

# Simple socket connectivity test to Cassandra
def test_cassandra_connectivity
  puts "Cassandra-CPP Socket Connectivity Test"
  puts "=" * 40
  
  hosts = ['localhost']
  port = 9042
  
  hosts.each do |host|
    begin
      puts "Testing connection to #{host}:#{port}..."
      
      Timeout.timeout(5) do
        socket = TCPSocket.new(host, port)
        socket.close
        puts "✅ Connection successful to #{host}:#{port}"
      end
      
    rescue Errno::ECONNREFUSED
      puts "❌ Connection refused to #{host}:#{port}"
      puts "   Make sure Cassandra is running: docker-compose up -d"
      
    rescue Timeout::Error
      puts "❌ Connection timeout to #{host}:#{port}"
      
    rescue StandardError => e
      puts "❌ Connection failed to #{host}:#{port}: #{e.message}"
    end
  end
  
  # Test both Cassandra nodes
  puts "\nTesting both Cassandra nodes..."
  [9042, 9043].each do |test_port|
    begin
      Timeout.timeout(5) do
        socket = TCPSocket.new('localhost', test_port)
        socket.close
        puts "✅ Cassandra node on port #{test_port} is reachable"
      end
    rescue Errno::ECONNREFUSED
      puts "❌ Cassandra node on port #{test_port} is not running"
    rescue StandardError => e
      puts "❌ Error connecting to port #{test_port}: #{e.message}"
    end
  end
  
  puts "\n" + "=" * 40
  puts "Socket connectivity test completed"
  puts "Next step: Install proper C++ driver and create native bindings"
end

test_cassandra_connectivity if __FILE__ == $PROGRAM_NAME