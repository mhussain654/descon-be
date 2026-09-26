# frozen_string_literal: true

# An inbound AI helpline call may never resolve to a known candidate/
# assignment (caller number unmatched, or verification never completed) but
# is still a loggable Communication row -- admins need to see "someone called
# and we couldn't identify them" in the central log, not have that event
# silently dropped because the schema demanded an assignment that doesn't
# exist yet. Every existing writer of this table (none yet in application
# code -- confirmed via repo-wide grep) already supplies a real assignment,
# so this is purely additive.
class MakeCommunicationsCandidateAssignmentOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :communications, :candidate_assignment_id, true
  end
end
