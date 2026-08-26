# frozen_string_literal: true

module Admin
  module Candidates
    class ImportService < ApplicationService
      def initialize(actor:, file:, request_id:)
        @actor = actor
        @file = file
        @request_id = request_id
      end

      def call
        rows = Imports::CsvFileParser.call(file: @file)
        result = Imports::Result.new(total_rows: rows.size)
        plan_rows(rows:, result:)

        persist_import!(result)
        result.to_h
      end

      private

      def plan_rows(rows:, result:)
        row_builder = Imports::RowBuilder.new(actor: @actor)
        duplicate_tracker = Imports::DuplicateTracker.new

        rows.each_with_index do |row, index|
          process_row(row_builder:, duplicate_tracker:, result:, row:, row_number: index + 2)
        end
      end

      def process_row(row_builder:, duplicate_tracker:, result:, row:, row_number:)
        row_plan = row_builder.call(row:, row_number:)

        return result.record_failed(row_number:, errors: [{ field: 'row', code: 'blank_row' }]) if row_plan.blank?
        return result.record_failed(row_number:, errors: row_plan.errors) if row_plan.invalid?

        record_duplicate_or_schedule(row_plan:, duplicate_tracker:, result:)
      end

      def persist_import!(result)
        persister = Imports::RowPersister.new

        ActiveRecord::Base.transaction do
          result.persistable_rows.each { |row_plan| persister.call(row_plan:, result:) }
          create_audit_event!(result:)
        end
      end

      def record_duplicate_or_schedule(row_plan:, duplicate_tracker:, result:)
        duplicate_error = duplicate_tracker.register(row_plan)
        return result.record_failed(row_number: row_plan.row_number, errors: [duplicate_error]) if duplicate_error

        result.schedule(row_plan)
      end

      def create_audit_event!(result:)
        AuditEvent.create!(
          actor: @actor,
          entity_type: 'User',
          entity_id: @actor.id,
          action_code: 'candidate_import_completed',
          request_id: @request_id,
          metadata: result.summary,
          occurred_at: Time.current
        )
      end
    end
  end
end
