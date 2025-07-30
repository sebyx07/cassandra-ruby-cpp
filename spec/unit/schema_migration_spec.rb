# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::Schema::Migration do
  let(:mock_session) { double('session') }
  let(:mock_schema) { double('schema') }
  let(:migration) { described_class.new(mock_session) }

  before do
    allow(CassandraCpp::Schema::Manager).to receive(:new).with(mock_session).and_return(mock_schema)
  end

  describe '#initialize' do
    it 'creates a migration with session and schema manager' do
      expect(migration.instance_variable_get(:@session)).to eq(mock_session)
      expect(migration.instance_variable_get(:@schema)).to eq(mock_schema)
    end
  end

  describe '#up and #down' do
    it 'raises NotImplementedError for up method' do
      expect { migration.up }.to raise_error(NotImplementedError, /Subclass must implement the 'up' method/)
    end

    it 'raises NotImplementedError for down method' do
      expect { migration.down }.to raise_error(NotImplementedError, /Subclass must implement the 'down' method/)
    end
  end

  describe '#migrate!' do
    it 'calls the up method' do
      expect(migration).to receive(:up)
      migration.migrate!
    end
  end

  describe '#rollback!' do
    it 'calls the down method' do
      expect(migration).to receive(:down)
      migration.rollback!
    end
  end

  describe 'schema manipulation methods' do
    describe '#create_table' do
      it 'delegates to schema manager' do
        expect(mock_schema).to receive(:create_table).with('users')
        migration.send(:create_table, :users)
      end
    end

    describe '#drop_table' do
      it 'delegates to schema manager with default options' do
        expect(mock_schema).to receive(:drop_table).with('users', if_exists: true)
        migration.send(:drop_table, :users)
      end

      it 'delegates to schema manager with custom options' do
        expect(mock_schema).to receive(:drop_table).with('users', if_exists: false)
        migration.send(:drop_table, :users, if_exists: false)
      end
    end

    describe '#add_column' do
      it 'delegates to schema manager' do
        expect(mock_schema).to receive(:add_column).with('users', 'email', :text)
        migration.send(:add_column, :users, :email, :text)
      end
    end

    describe '#drop_column' do
      it 'delegates to schema manager' do
        expect(mock_schema).to receive(:drop_column).with('users', 'email')
        migration.send(:drop_column, :users, :email)
      end
    end

    describe '#create_index' do
      it 'delegates to schema manager with default options' do
        expect(mock_schema).to receive(:create_index).with('users', 'email', index_name: nil)
        migration.send(:create_index, :users, :email)
      end

      it 'delegates to schema manager with custom name' do
        expect(mock_schema).to receive(:create_index).with('users', 'email', index_name: 'custom_idx')
        migration.send(:create_index, :users, :email, index_name: :custom_idx)
      end
    end

    describe '#drop_index' do
      it 'delegates to schema manager' do
        expect(mock_schema).to receive(:drop_index).with('email_idx')
        migration.send(:drop_index, :email_idx)
      end
    end

    describe '#execute' do
      it 'delegates to session' do
        expect(mock_session).to receive(:execute).with('SELECT * FROM users')
        migration.send(:execute, 'SELECT * FROM users')
      end
    end

    describe '#execute_with_params' do
      it 'delegates to session with parameters' do
        expect(mock_session).to receive(:execute).with('SELECT * FROM users WHERE id = ?', 'user-123')
        migration.send(:execute_with_params, 'SELECT * FROM users WHERE id = ?', ['user-123'])
      end
    end

    describe '#table_exists?' do
      it 'delegates to schema manager' do
        expect(mock_schema).to receive(:table_exists?).with('users').and_return(true)
        result = migration.send(:table_exists?, :users)
        expect(result).to be true
      end
    end

    describe '#columns' do
      it 'delegates to schema manager' do
        columns_data = [{ name: 'id', type: 'uuid' }]
        expect(mock_schema).to receive(:columns).with('users').and_return(columns_data)
        result = migration.send(:columns, :users)
        expect(result).to eq(columns_data)
      end
    end
  end

  describe 'version and name extraction' do
    let(:versioned_migration_class) do
      Class.new(CassandraCpp::Schema::Migration) do
        def self.name
          '20240101120000_CreateUsersTable'
        end
      end
    end

    let(:versioned_migration) { versioned_migration_class.new(mock_session) }

    describe '#version' do
      it 'extracts version from class name' do
        expect(versioned_migration.version).to eq('20240101120000')
      end

      it 'returns nil for class without version' do
        expect(migration.version).to be_nil
      end
    end

    describe '#name' do
      it 'extracts name from class name' do
        expect(versioned_migration.name).to eq('20240101120000_create_users_table')
      end
    end
  end
end

RSpec.describe CassandraCpp::Schema::MigrationRunner do
  let(:mock_session) { double('session') }
  let(:mock_schema) { double('schema') }
  let(:migration_runner) { described_class.new(mock_session) }

  before do
    allow(CassandraCpp::Schema::Manager).to receive(:new).with(mock_session).and_return(mock_schema)
    allow(mock_schema).to receive(:table_exists?).with('schema_migrations').and_return(true)
  end

  describe '#initialize' do
    it 'creates migration runner with session' do
      expect(migration_runner.instance_variable_get(:@session)).to eq(mock_session)
    end

    context 'when schema_migrations table does not exist' do
      before do
        allow(mock_schema).to receive(:table_exists?).with('schema_migrations').and_return(false)
      end

      it 'creates the schema_migrations table' do
        expect(mock_session).to receive(:execute).with(/CREATE TABLE schema_migrations/)
        described_class.new(mock_session)
      end
    end
  end

  describe '#status' do
    let(:migration_files) do
      [
        '/path/to/20240101120000_create_users.rb',
        '/path/to/20240102120000_add_email_to_users.rb',
        '/path/to/20240103120000_create_posts.rb'
      ]
    end
    
    let(:applied_versions) { ['20240101120000', '20240103120000'] }

    before do
      allow(migration_runner).to receive(:find_migration_files).and_return(migration_files)
      allow(migration_runner).to receive(:get_applied_versions).and_return(applied_versions)
    end

    it 'returns migration status information' do
      status = migration_runner.status
      
      expect(status).to eq([
        { version: '20240101120000', name: '20240101120000_create_users', status: 'applied' },
        { version: '20240102120000', name: '20240102120000_add_email_to_users', status: 'pending' },
        { version: '20240103120000', name: '20240103120000_create_posts', status: 'applied' }
      ])
    end
  end

  describe 'private methods' do
    describe '#get_applied_versions' do
      let(:mock_result) do
        [
          { 'version' => '20240101120000' },
          { 'version' => '20240102120000' }
        ]
      end

      it 'queries schema_migrations table' do
        expect(mock_session).to receive(:execute)
          .with('SELECT version FROM schema_migrations')
          .and_return(mock_result)

        versions = migration_runner.send(:get_applied_versions)
        expect(versions).to eq(['20240101120000', '20240102120000'])
      end
    end

    describe '#record_migration' do
      it 'inserts migration record' do
        expect(mock_session).to receive(:execute)
          .with(
            'INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?)',
            '20240101120000', 'create_users', instance_of(Time)
          )

        migration_runner.send(:record_migration, '20240101120000', 'create_users')
      end
    end

    describe '#remove_migration_record' do
      it 'deletes migration record' do
        expect(mock_session).to receive(:execute)
          .with('DELETE FROM schema_migrations WHERE version = ?', '20240101120000')

        migration_runner.send(:remove_migration_record, '20240101120000')
      end
    end

    describe '#extract_version_from_filename' do
      it 'extracts version from migration filename' do
        filename = '/path/to/20240101120000_create_users.rb'
        version = migration_runner.send(:extract_version_from_filename, filename)
        expect(version).to eq('20240101120000')
      end
    end

    describe '#migrations_path' do
      it 'returns default migrations path' do
        path = migration_runner.send(:migrations_path)
        expect(path).to eq(File.join(Dir.pwd, 'db', 'migrations'))
      end
    end
  end
end