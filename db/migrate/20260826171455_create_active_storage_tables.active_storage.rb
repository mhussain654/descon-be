# frozen_string_literal: true

# This migration comes from active_storage (originally 20170806125915)
class CreateActiveStorageTables < ActiveRecord::Migration[7.0]
  def change
    primary_key_type, foreign_key_type = primary_and_foreign_key_types

    create_blobs_table(primary_key_type)
    create_attachments_table(primary_key_type, foreign_key_type)
    create_variant_records_table(primary_key_type, foreign_key_type)
  end

  private

  def create_blobs_table(primary_key_type)
    create_table :active_storage_blobs, id: primary_key_type do |t|
      define_blob_columns(t)

      add_created_at_column(t)
      t.index [:key], unique: true
    end
  end

  def create_attachments_table(primary_key_type, foreign_key_type)
    create_table :active_storage_attachments, id: primary_key_type do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false, type: foreign_key_type
      t.references :blob, null: false, type: foreign_key_type

      add_created_at_column(t)
      t.index %i[record_type record_id name blob_id],
              name: :index_active_storage_attachments_uniqueness,
              unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end

  def create_variant_records_table(primary_key_type, foreign_key_type)
    create_table :active_storage_variant_records, id: primary_key_type do |t|
      t.belongs_to :blob, null: false, index: false, type: foreign_key_type
      t.string :variation_digest, null: false

      t.index %i[blob_id variation_digest],
              name: :index_active_storage_variant_records_uniqueness,
              unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end

  def define_blob_columns(table)
    table.string :key, null: false
    table.string :filename, null: false
    table.string :content_type
    table.text :metadata
    table.string :service_name, null: false
    table.bigint :byte_size, null: false
    table.string :checksum
  end

  def add_created_at_column(table)
    return table.datetime(:created_at, precision: 6, null: false) if connection.supports_datetime_with_precision?

    table.datetime :created_at, null: false
  end

  def primary_and_foreign_key_types
    config = Rails.configuration.generators
    setting = config.options[config.orm][:primary_key_type]
    primary_key_type = setting || :primary_key
    foreign_key_type = setting || :bigint

    [primary_key_type, foreign_key_type]
  end
end
