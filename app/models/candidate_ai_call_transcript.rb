# frozen_string_literal: true

# The verbatim transcript of one AI voice call, kept off CandidateAiCall's
# own row (AGENTS.md: "avoid loading unnecessary columns") since a call
# transcript is a verbatim recording of a candidate discussing personal/case
# details -- often more sensitive than the header row every admin list/
# detail view loads.
#
# Deliberately NOT `include ImmutableRecord`: that concern has no escape
# hatch, and a transcript that may contain CNIC/passport/medical/financial
# information cannot be architected as permanently undeletable -- it must
# stay purgeable under a retention policy. Instead, #assert_only_purge_fields_changed!
# allows exactly one kind of update after creation: nulling `transcript`/
# `recording_reference` and stamping `redacted_at`/`purged_at` (see
# AiCalls::PurgeTranscriptService, the only caller allowed to update this
# model). Every other field, and every attempt to *set* transcript content
# (as opposed to clearing it), is blocked the same way ImmutableRecord
# blocks all changes.
class CandidateAiCallTranscript < ApplicationRecord
  PURGE_ONLY_ATTRIBUTES = %w[transcript recording_reference redacted_at purged_at updated_at].freeze

  encrypts :transcript

  belongs_to :candidate_ai_call

  before_update :assert_only_purge_fields_changed!
  before_update :assert_content_only_cleared_not_replaced!
  before_destroy :raise_readonly_record

  private

  def assert_only_purge_fields_changed!
    return if (changed_attribute_names_to_save - PURGE_ONLY_ATTRIBUTES).empty?

    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} only permits purge/redaction updates after creation"
  end

  # `transcript`/`recording_reference` may only transition to nil (a purge)
  # via #update -- never be set for the first time or replaced with a
  # different value outside of the original #create!.
  def assert_content_only_cleared_not_replaced!
    %w[transcript recording_reference].each do |attribute|
      next unless will_save_change_to_attribute?(attribute)
      next if self[attribute].nil?

      raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} content can only be cleared, never replaced"
    end
  end

  def raise_readonly_record
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} records cannot be destroyed, only purged"
  end
end
