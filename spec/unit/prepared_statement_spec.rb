# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CassandraCpp::PreparedStatement do
  let(:native_prepared) { double('NativePreparedStatement') }
  let(:query) { 'INSERT INTO users (id, name, email) VALUES (?, ?, ?)' }
  let(:prepared_statement) { described_class.new(native_prepared, query) }
  
  describe '#initialize' do
    it 'stores the query and counts parameters' do
      expect(prepared_statement.query).to eq(query)
      expect(prepared_statement.param_count).to eq(3)
    end
    
    context 'parameter counting' do
      it 'counts zero parameters correctly' do
        stmt = described_class.new(native_prepared, 'SELECT * FROM users')
        expect(stmt.param_count).to eq(0)
        expect(stmt.has_params?).to be(false)
      end
      
      it 'ignores ? inside single quotes' do
        stmt = described_class.new(native_prepared, "SELECT * FROM users WHERE name = 'test?' AND age = ?")
        expect(stmt.param_count).to eq(1)
      end
      
      it 'ignores ? inside double quotes' do
        stmt = described_class.new(native_prepared, 'SELECT * FROM users WHERE name = "test?" AND age = ?')
        expect(stmt.param_count).to eq(1)
      end
      
      it 'handles escaped quotes' do
        stmt = described_class.new(native_prepared, "SELECT * FROM users WHERE name = 'test\\'?' AND age = ?")
        expect(stmt.param_count).to eq(1)
      end
      
      it 'counts multiple parameters' do
        stmt = described_class.new(native_prepared, 'INSERT INTO test (a, b, c, d, e) VALUES (?, ?, ?, ?, ?)')
        expect(stmt.param_count).to eq(5)
      end
    end
  end
  
  describe '#execute' do
    let(:native_statement) { double('NativeStatement') }
    let(:result_rows) { [{ 'id' => '123', 'name' => 'Test' }] }
    
    before do
      allow(native_prepared).to receive(:bind).and_return(native_statement)
      allow(native_statement).to receive(:bind)
      allow(native_statement).to receive(:execute).and_return(result_rows)
    end
    
    it 'creates a bound statement and executes it' do
      expect(native_prepared).to receive(:bind).and_return(native_statement)
      expect(native_statement).to receive(:bind).with(0, '123')
      expect(native_statement).to receive(:bind).with(1, 'John')
      expect(native_statement).to receive(:bind).with(2, 'john@example.com')
      expect(native_statement).to receive(:execute).and_return(result_rows)
      
      result = prepared_statement.execute('123', 'John', 'john@example.com')
      expect(result).to be_a(CassandraCpp::Result)
    end
    
    it 'validates parameter count' do
      expect {
        prepared_statement.execute('123', 'John') # Missing email
      }.to raise_error(ArgumentError, 'Wrong number of parameters: expected 3, got 2')
      
      expect {
        prepared_statement.execute('123', 'John', 'john@example.com', 'extra')
      }.to raise_error(ArgumentError, 'Wrong number of parameters: expected 3, got 4')
    end
    
    it 'handles nil parameters' do
      expect(native_statement).to receive(:bind).with(0, '123')
      expect(native_statement).to receive(:bind).with(1, nil)
      expect(native_statement).to receive(:bind).with(2, 'john@example.com')
      
      prepared_statement.execute('123', nil, 'john@example.com')
    end
    
    it 'returns a Result object' do
      result = prepared_statement.execute('123', 'John', 'john@example.com')
      expect(result).to be_a(CassandraCpp::Result)
    end
  end
  
  describe '#execute_with_params' do
    it 'raises NotImplementedError' do
      expect {
        prepared_statement.execute_with_params(id: '123', name: 'John')
      }.to raise_error(NotImplementedError, 'Named parameters are not yet supported')
    end
  end
  
  describe '#has_params?' do
    it 'returns true when statement has parameters' do
      expect(prepared_statement.has_params?).to be(true)
    end
    
    it 'returns false when statement has no parameters' do
      stmt = described_class.new(native_prepared, 'SELECT * FROM users')
      expect(stmt.has_params?).to be(false)
    end
  end
end