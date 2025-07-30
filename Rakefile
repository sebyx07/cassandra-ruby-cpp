# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

# Default task
task default: [:compile, :spec]

# Compilation task
desc 'Compile the native extension'
task :compile do
  Dir.chdir('ext/cassandra_cpp') do
    system('ruby extconf.rb') || raise('extconf.rb failed')
    system('make') || raise('make failed')
  end
  
  # Copy to lib directory
  FileUtils.mkdir_p('lib/cassandra_cpp')
  FileUtils.cp('ext/cassandra_cpp/cassandra_cpp.so', 'lib/cassandra_cpp/') if File.exist?('ext/cassandra_cpp/cassandra_cpp.so')
  FileUtils.cp('ext/cassandra_cpp/cassandra_cpp.bundle', 'lib/cassandra_cpp/') if File.exist?('ext/cassandra_cpp/cassandra_cpp.bundle')
end

# Clean task
desc 'Clean compiled files'
task :clean do
  Dir.chdir('ext/cassandra_cpp') do
    system('make clean') if File.exist?('Makefile')
    FileUtils.rm_f(['cassandra_cpp.so', 'cassandra_cpp.bundle', 'cassandra_cpp.o', 'Makefile', 'mkmf.log'])
  end
  
  FileUtils.rm_f(['lib/cassandra_cpp/cassandra_cpp.so', 'lib/cassandra_cpp/cassandra_cpp.bundle'])
end

# Test tasks
RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = 'spec/**/*_spec.rb'
  task.rspec_opts = '--format documentation --color'
end

RSpec::Core::RakeTask.new('spec:unit') do |task|
  task.pattern = 'spec/unit/**/*_spec.rb'
  task.rspec_opts = '--format documentation --color'
end

RSpec::Core::RakeTask.new('spec:integration') do |task|
  task.pattern = 'spec/integration/**/*_spec.rb'
  task.rspec_opts = '--format documentation --color'
end

RSpec::Core::RakeTask.new('spec:fast') do |task|
  task.pattern = 'spec/unit/**/*_spec.rb'
  task.rspec_opts = '--format progress'
end

desc 'Run tests with coverage'
task 'spec:coverage' do
  ENV['COVERAGE'] = 'true'
  Rake::Task['spec'].invoke
end

desc 'Run performance benchmarks'
task 'spec:performance' do
  ENV['PROFILE_TESTS'] = 'true'
  Rake::Task['spec:integration'].invoke
end

# Development tasks
desc 'Setup development environment'
task :setup do
  system('bin/setup') || raise('Setup failed')
end

desc 'Start development container'
task 'dev:up' do
  system('docker-compose up -d cassandra-cpp-dev') || raise('Failed to start dev container')
end

desc 'Stop development container'
task 'dev:down' do
  system('docker-compose down')
end

desc 'Enter development container'
task 'dev:shell' do
  system('docker exec -it cassandra-cpp-dev bash')
end

desc 'Run tests in container'
task 'dev:test' do
  system('docker exec -it cassandra-cpp-dev bundle exec rake spec') || raise('Tests failed in container')
end

desc 'Build container and run tests'
task 'dev:test:full' do
  system('docker-compose build cassandra-cpp-dev') || raise('Failed to build container')
  system('docker-compose up -d cassandra-1 cassandra-2') || raise('Failed to start Cassandra')
  
  # Wait for Cassandra to be ready
  puts 'Waiting for Cassandra to be ready...'
  60.times do
    if system('docker exec cassandra-node-1 cqlsh -e "describe keyspaces" > /dev/null 2>&1')
      break
    end
    sleep 2
  end
  
  system('docker-compose run --rm cassandra-cpp-dev bundle exec rake spec') || raise('Tests failed')
end

# Documentation tasks
desc 'Generate documentation'
task :docs do
  system('bundle exec yard doc')
end

desc 'Serve documentation'
task 'docs:serve' do
  system('bundle exec yard server --reload')
end

# Utility tasks
desc 'Show native extension status'
task :status do
  require_relative 'lib/cassandra_cpp'
  
  puts "Cassandra-CPP Status:"
  puts "  Native Extension: #{CassandraCpp.native_extension_loaded? ? '✅ Loaded' : '❌ Not loaded'}"
  puts "  Version: #{CassandraCpp::VERSION}"
  
  if CassandraCpp.native_extension_loaded?
    puts "  Native Classes:"
    puts "    - NativeCluster: #{defined?(CassandraCpp::NativeCluster) ? '✅' : '❌'}"
    puts "    - NativeSession: #{defined?(CassandraCpp::NativeSession) ? '✅' : '❌'}"
    puts "    - Error: #{defined?(CassandraCpp::Error) ? '✅' : '❌'}"
  end
  
  # Test Cassandra connectivity
  begin
    cluster = CassandraCpp::Cluster.build
    session = cluster.connect
    result = session.execute('SELECT release_version FROM system.local')
    version = result.first['release_version']
    session.close
    cluster.close
    puts "  Cassandra: ✅ Connected (v#{version})"
  rescue => e
    puts "  Cassandra: ❌ Not available (#{e.message})"
  end
end

desc 'Run POC demonstrations'
task :demo do
  Dir['tmp/pocs/*.rb'].each do |file|
    next if file.include?('README')
    
    puts "\n" + "=" * 60
    puts "Running: #{File.basename(file)}"
    puts "=" * 60
    
    system("ruby #{file}")
  end
end