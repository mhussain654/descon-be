# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Maintenance::PurgedTableOrder do
  # Tables and the tables each one references.
  def connection_with(references)
    keys = references.transform_values do |targets|
      targets.map do |to|
        Struct.new(:to_table, :column).new(to, "#{to}_id")
      end
    end
    instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, tables: references.keys).tap do |connection|
      allow(connection).to receive(:foreign_keys) { |table| keys.fetch(table, []) }
    end
  end

  it 'puts each table before the tables it references' do
    connection = connection_with('parents' => [], 'children' => ['parents'], 'grandchildren' => ['children'])

    expect(described_class.new(%w[parents children grandchildren], connection:).ordered)
      .to eq(%w[grandchildren children parents])
  end

  it 'refuses a foreign key cycle' do
    connection = connection_with('a' => ['b'], 'b' => ['a'])

    expect { described_class.new(%w[a b], connection:).ordered }.to raise_error(described_class::CycleError, /a, b/)
  end

  it 'lists outside tables that point into the set' do
    connection = connection_with('kept' => ['purged'], 'purged' => [])

    expect(described_class.new(%w[purged], connection:).outside_references).to eq(['kept.purged_id'])
  end
end
