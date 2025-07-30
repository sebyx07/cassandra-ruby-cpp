# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe CassandraCpp do
  describe '.native_extension_loaded?' do
    it 'returns a boolean' do
      result = described_class.native_extension_loaded?
      expect([true, false]).to include(result)
    end

    context 'when native extension is available' do
      it 'defines native classes' do
        skip unless described_class.native_extension_loaded?
        
        expect(defined?(CassandraCpp::NativeCluster)).to be_truthy
        expect(defined?(CassandraCpp::NativeSession)).to be_truthy
        expect(defined?(CassandraCpp::Error)).to be_truthy
      end

      it 'defines consistency constants' do
        skip unless described_class.native_extension_loaded?
        
        expect(CassandraCpp::CONSISTENCY_ONE).to be_a(Integer)
        expect(CassandraCpp::CONSISTENCY_QUORUM).to be_a(Integer)
        expect(CassandraCpp::CONSISTENCY_ALL).to be_a(Integer)
      end
    end
  end

  describe '.configure' do
    it 'yields self for configuration' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class)
    end
  end

  describe '.logger' do
    it 'returns a logger instance' do
      logger = described_class.logger
      expect(logger).to respond_to(:info)
      expect(logger).to respond_to(:error)
    end

    it 'allows setting custom logger' do
      original_logger = described_class.logger
      custom_logger = Logger.new(StringIO.new)
      
      described_class.configure do |config|
        config.logger = custom_logger
      end
      
      expect(described_class.logger).to eq(custom_logger)
      
      # Reset to avoid affecting other tests
      described_class.logger = original_logger
    end
  end

  describe 'version' do
    it 'has a version number' do
      expect(CassandraCpp::VERSION).not_to be nil
      expect(CassandraCpp::VERSION).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe 'exception hierarchy' do
    it 'defines proper exception classes' do
      expect(CassandraCpp::Error).to be < StandardError
      expect(CassandraCpp::ConnectionError).to be < CassandraCpp::Error
      expect(CassandraCpp::QueryError).to be < CassandraCpp::Error
      expect(CassandraCpp::TimeoutError).to be < CassandraCpp::Error
    end
  end

  describe 'autoload setup' do
    it 'autoloads main classes' do
      expect(defined?(CassandraCpp::Cluster)).to be_truthy
      expect(defined?(CassandraCpp::Session)).to be_truthy
      expect(defined?(CassandraCpp::Result)).to be_truthy
    end
  end
end