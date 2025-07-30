#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to check for potential secrets in code
# Used by overcommit pre-commit hook

require 'pathname'

# Patterns that might indicate secrets
SECRET_PATTERNS = [
  # API keys
  /api[_-]?key\s*[=:]\s*['"]\w+['"]/i,
  /secret[_-]?key\s*[=:]\s*['"]\w+['"]/i,
  /access[_-]?token\s*[=:]\s*['"]\w+['"]/i,
  
  # Passwords
  /password\s*[=:]\s*['"][^'"]{8,}['"]/i,
  /passwd\s*[=:]\s*['"][^'"]{8,}['"]/i,
  
  # Database URLs with credentials
  %r{[a-z]+://[^:]+:[^@]+@[^/]+}i,
  
  # Private keys
  /-----BEGIN [A-Z ]+ PRIVATE KEY-----/,
  /-----BEGIN RSA PRIVATE KEY-----/,
  
  # AWS
  /AKIA[0-9A-Z]{16}/,
  /aws[_-]?secret[_-]?access[_-]?key/i,
  
  # Slack tokens
  /xox[baprs]-[0-9a-zA-Z-]+/,
  
  # GitHub tokens
  /gh[pousr]_[0-9a-zA-Z]{36}/,
  
  # Generic hex secrets (24+ chars)
  /[a-f0-9]{24,}/i
].freeze

# Files to check
def files_to_check
  if ARGV.empty?
    # Check all Ruby files
    Dir.glob('**/*.rb').reject do |file|
      file.start_with?('vendor/') || 
      file.start_with?('tmp/') ||
      file.start_with?('coverage/')
    end
  else
    ARGV.select { |file| file.end_with?('.rb') }
  end
end

# Check if line contains secrets
def contains_secret?(line, file_path)
  # Skip comments that are obviously documentation
  return false if line.strip.start_with?('#') && 
                  (line.include?('example') || line.include?('TODO') || line.include?('FIXME'))
  
  # Skip test files with obvious fake data
  return false if file_path.include?('spec/') && 
                  (line.include?('fake') || line.include?('test') || line.include?('example'))
  
  SECRET_PATTERNS.any? { |pattern| line.match?(pattern) }
end

# Main execution
def main
  violations = []
  
  files_to_check.each do |file_path|
    next unless File.exist?(file_path)
    
    File.readlines(file_path, chomp: true).each_with_index do |line, index|
      if contains_secret?(line, file_path)
        violations << {
          file: file_path,
          line: index + 1,
          content: line.strip
        }
      end
    end
  end
  
  if violations.empty?
    puts "✅ No potential secrets found"
    exit 0
  else
    puts "❌ Potential secrets detected:"
    violations.each do |violation|
      puts "  #{violation[:file]}:#{violation[:line]} - #{violation[:content]}"
    end
    puts
    puts "If these are not actual secrets:"
    puts "1. Use environment variables instead of hardcoded values"
    puts "2. Move to encrypted configuration files"
    puts "3. Add comments to indicate test/example data"
    puts "4. Update this script to ignore false positives"
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME