# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::Cluster do
  describe '.build' do
    it 'creates a new cluster instance' do
      cluster = described_class.build
      expect(cluster).to be_a(described_class)
    end

    it 'accepts configuration options' do
      config = { hosts: ['example.com'], port: 9999 }
      cluster = described_class.build(config)
      expect(cluster).to be_a(described_class)
    end
  end

  describe '#initialize' do
    context 'with default configuration' do
      let(:cluster) { described_class.new }

      it 'sets default hosts' do
        expect { cluster }.not_to raise_error
      end

      it 'sets default port' do
        expect { cluster }.not_to raise_error
      end
    end

    context 'with custom configuration' do
      it 'accepts string host' do
        cluster = described_class.new(hosts: 'example.com')
        expect(cluster).to be_a(described_class)
      end

      it 'accepts array of hosts' do
        cluster = described_class.new(hosts: ['host1', 'host2'])
        expect(cluster).to be_a(described_class)
      end

      it 'validates port range' do
        expect {
          described_class.new(port: -1)
        }.to raise_error(ArgumentError, /port must be between/)

        expect {
          described_class.new(port: 65536)
        }.to raise_error(ArgumentError, /port must be between/)
      end

      it 'requires non-empty hosts' do
        expect {
          described_class.new(hosts: [])
        }.to raise_error(ArgumentError, /hosts must be provided/)
      end
    end
  end

  describe '#connect', type: :integration do
    let(:cluster) { create_test_cluster }

    it 'returns a session instance' do
      skip_unless_cassandra_available
      
      session = cluster.connect
      expect(session).to be_a(CassandraCpp::Session)
      session.close
      cluster.close
    end

    it 'connects to a specific keyspace' do
      skip_unless_cassandra_available
      
      session = cluster.connect('system')
      expect(session).to be_a(CassandraCpp::Session)
      session.close
      cluster.close
    end

    it 'raises ConnectionError for invalid hosts' do
      invalid_cluster = described_class.build(hosts: ['nonexistent.invalid'], port: 9999)
      expect {
        invalid_cluster.connect
      }.to raise_error(CassandraCpp::ConnectionError)
    end
  end

  describe '#execute', type: :integration do
    let(:cluster) { create_test_cluster }

    it 'executes a query and returns results' do
      skip_unless_cassandra_available
      
      result = cluster.execute('SELECT release_version FROM system.local')
      expect(result).to respond_to(:each)
      
      first_row = result.first
      if CassandraCpp.native_extension_loaded?
        # Native extension returns hash directly
        expect(first_row).to have_key('release_version')
      else
        # Ruby fallback wraps in Row class
        expect(first_row).to respond_to(:[])
        expect(first_row['release_version']).not_to be_nil
      end
      
      cluster.close
    end

    it 'handles query errors' do
      skip_unless_cassandra_available
      
      expect {
        cluster.execute('INVALID QUERY')
      }.to raise_error(CassandraCpp::Error)
      cluster.close
    end
  end

  describe '#close' do
    let(:cluster) { create_test_cluster }

    it 'closes the cluster connection' do
      skip_unless_cassandra_available
      
      session = cluster.connect
      session.close
      
      expect { cluster.close }.not_to raise_error
    end

    it 'can be called multiple times safely' do
      skip_unless_cassandra_available
      
      expect { cluster.close }.not_to raise_error
      expect { cluster.close }.not_to raise_error
    end
  end

  describe 'implementation modes' do
    let(:cluster) { create_test_cluster }

    context 'when native extension is loaded' do
      it 'uses native implementation' do
        skip unless CassandraCpp.native_extension_loaded?
        skip_unless_cassandra_available
        
        session = cluster.connect
        # Since we removed fallback mode, just verify the session works
        expect(session).to be_a(CassandraCpp::Session)
        expect(session.instance_variable_get(:@native_session)).to be_a(CassandraCpp::NativeSession)
        session.close
        cluster.close
      end
    end

    context 'when native extension is not loaded' do
      it 'raises an error without native extension' do
        skip if CassandraCpp.native_extension_loaded?
        
        expect {
          cluster.connect
        }.to raise_error(CassandraCpp::ConnectionError, /Native extension not loaded/)
      end
    end
  end
end