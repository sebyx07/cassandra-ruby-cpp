# frozen_string_literal: true

require_relative 'lib/cassandra_cpp/version'

Gem::Specification.new do |spec|
  spec.name = 'cassandra-cpp'
  spec.version = CassandraCpp::VERSION
  spec.authors = ['Cassandra-CPP Team']
  spec.email = ['team@cassandra-cpp.example.com']

  spec.summary = 'High-performance Ruby driver for Apache Cassandra using native C++ bindings'
  spec.description = <<~DESC
    Cassandra-CPP is a high-performance Ruby gem that provides seamless integration 
    with Apache Cassandra through native C++ bindings. By leveraging the DataStax C++ 
    driver, this gem delivers exceptional performance while maintaining Ruby's 
    developer-friendly interface.
  DESC
  
  spec.homepage = 'https://github.com/your-org/cassandra-cpp'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['documentation_uri'] = "#{spec.homepage}/blob/main/docs"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Development dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rake-compiler', '~> 1.2'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.57'
  spec.add_development_dependency 'yard', '~> 0.9'

  # Extensions
  spec.extensions = ['ext/cassandra_cpp/extconf.rb']

  # Metadata
  spec.metadata['rubygems_mfa_required'] = 'true'
end