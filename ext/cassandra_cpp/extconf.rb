#!/usr/bin/env ruby
# frozen_string_literal: true

require 'mkmf'

# Extension configuration for Cassandra-CPP native bindings

# Check for required libraries
abort 'ERROR: Missing libcassandra. Please install DataStax C++ driver.' unless have_library('cassandra')

# Check for required headers
abort 'ERROR: Missing cassandra.h header.' unless have_header('cassandra.h')

# Set up compiler flags
$CPPFLAGS += ' -std=c++11'
$CPPFLAGS += ' -DCPP_DRIVER_VERSION="2.16.2"'

# Enable optimizations for production
$CPPFLAGS += ' -O3 -DNDEBUG' unless ENV['DEBUG']

# Link against required libraries
have_library('cassandra')
have_library('pthread')
have_library('ssl')
have_library('crypto')
have_library('z')
have_library('uv')

# Check for pkg-config
if find_executable('pkg-config')
  pkg_config('cassandra')
end

# Platform-specific configurations
case RUBY_PLATFORM
when /darwin/
  # macOS specific settings
  $LDFLAGS += ' -framework CoreFoundation'
when /linux/
  # Linux specific settings
  $LDFLAGS += ' -lrt'
end

# Define source files
$srcs = [
  "cassandra_cpp.cpp",
  "common.cpp",
  "cluster.cpp",
  "session.cpp",
  "prepared_statement.cpp",
  "statement.cpp",
  "batch.cpp"
]

# Create the Makefile
create_makefile('cassandra_cpp/cassandra_cpp')