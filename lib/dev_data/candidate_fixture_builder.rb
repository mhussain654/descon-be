# frozen_string_literal: true

require 'factory_bot'

module DevData
  # Builds one candidate + assignment plus every domain record a QaDataSeeder::Profile asks
  # for (stage history, documents, QVC, visa, protection, flight, payment, AI call). Split out
  # of QaDataSeeder purely to keep each class a manageable size -- see QaDataSeeder's doc
  # comment for why this lives under lib/, not app/services/.
  # rubocop:disable Metrics/ClassLength
  class CandidateFixtureBuilder
    include FactoryBot::Syntax::Methods

    STAGE_CODES = WorkflowStage::CANONICAL_STAGES.map { |stage| stage.fetch(:code) }.freeze

    # One optional builder per Profile field -- looping over this table instead of a chain of
    # `if profile.x` calls keeps dispatch data-driven rather than branchy.
    OPTIONAL_BUILDERS = {
      documents: :build_documents!, qvc: :build_qvc!, visa: :build_visa!, protection: :build_protection!,
      flight: :build_flight!, payment: :build_payment!
    }.freeze

    def initialize(document_types:, seed_tag:)
      @document_types = document_types
      @seed_tag = seed_tag
    end

    def build(profile:, index:, actor:, reference:)
      candidate = build_candidate(profile, index, actor)
      assignment = build_assignment(candidate, actor, reference)

      build_stage_history!(assignment, profile.stage, actor)
      apply_optional_builders(profile, assignment, actor)
      build_ai_call!(candidate, assignment, profile.ai_call, actor) if profile.ai_call

      { candidate:, assignment:, profile: }
    end

    private

    def apply_optional_builders(profile, assignment, actor)
      OPTIONAL_BUILDERS.each do |field, method_name|
        value = profile[field]
        send(method_name, assignment, value, actor) if value
      end
    end

    def build_candidate(profile, index, actor)
      create(:candidate, full_name: "#{@seed_tag} Candidate #{format('%02d', index + 1)} (#{profile.stage})",
                         created_by: actor)
    end

    def build_assignment(candidate, actor, reference)
      create(:candidate_assignment, candidate:, created_by: actor, country: reference.fetch(:countries).sample,
                                    project: reference.fetch(:projects).sample, craft: reference.fetch(:crafts).sample)
    end

    # Walks the fixed stage sequence from `registered` up to `target_code`, leaving a realistic
    # CandidateStageHistory trail behind -- not just the assignment landing directly on the final
    # stage -- so the per-candidate workflow-history admin tab has something to show.
    def build_stage_history!(assignment, target_code, actor)
      target_index = STAGE_CODES.index(target_code)
      return if target_index.zero?

      base_time = 30.days.ago
      (1..target_index).each { |i| create_stage_history_step(assignment, i, actor, base_time) }
      assignment.update!(current_workflow_stage: WorkflowStage.find_by!(code: target_code))
    end

    def create_stage_history_step(assignment, index, actor, base_time)
      create(:candidate_stage_history, candidate_assignment: assignment,
                                       from_workflow_stage: WorkflowStage.find_by!(code: STAGE_CODES[index - 1]),
                                       to_workflow_stage: WorkflowStage.find_by!(code: STAGE_CODES[index]),
                                       actor:, occurred_at: base_time + (index * 2).days)
    end

    # ------------------------------------------------------------------------
    # Documents
    # ------------------------------------------------------------------------

    def build_documents!(assignment, variation, actor)
      send("build_documents_#{variation}!", assignment, actor)
    end

    def build_documents_none!(_assignment, _actor) = nil

    def build_documents_partial!(assignment, actor)
      @document_types.first(3).each { |type| document(assignment, type, :uploaded, actor) }
    end

    def build_documents_all_uploaded!(assignment, actor)
      @document_types.each { |type| document(assignment, type, :uploaded, actor) }
    end

    def build_documents_one_rejected!(assignment, actor)
      @document_types.each_with_index { |type, i| document(assignment, type, i.zero? ? :rejected : :uploaded, actor) }
    end

    def build_documents_all_pending_review!(assignment, actor)
      @document_types.each { |type| document(assignment, type, :under_verification, actor) }
    end

    def build_documents_mixed_pending_and_rejected!(assignment, actor)
      @document_types.each_with_index do |type, i|
        document(assignment, type, i.even? ? :under_verification : :rejected, actor)
      end
    end

    def build_documents_all_verified!(assignment, actor)
      @document_types.each { |type| document(assignment, type, :verified, actor) }
    end

    # PCC (police_character) expiry is computed automatically from `issued_on` (+6 months) --
    # there's no separate status column to set after the fact, so an "expired" PCC just needs an
    # issue date old enough that its auto-computed expiry has already passed.
    def build_documents_expired_pcc!(assignment, actor)
      @document_types.each do |type|
        pcc = type.code == CandidateDocument::PCC_REQUIREMENT_CODE
        document(assignment, type, :verified, actor, issued_on: pcc ? 8.months.ago.to_date : nil)
      end
    end

    def document(assignment, type, status, actor, issued_on: nil)
      attrs = { candidate_assignment: assignment, document_type: type, uploaded_by: actor, status_code: status.to_s }
      attrs.merge!(document_status_attributes(status, actor))
      attrs[:issued_on] = issued_on || default_issued_on(type)
      create(:candidate_document, **attrs)
    end

    # `police_character` documents require `issued_on` regardless of status (see
    # PoliceCharacterCompliance's presence validation); every other type leaves it nil.
    def default_issued_on(type)
      2.months.ago.to_date if type.code == CandidateDocument::PCC_REQUIREMENT_CODE
    end

    def document_status_attributes(status, actor)
      case status
      when :verified then { verified_by: actor, verified_at: 2.days.ago }
      when :rejected
        { verified_by: actor, verified_at: 2.days.ago,
          rejection_reason: 'Document image is unclear, please re-upload.' }
      else {}
      end
    end

    # ------------------------------------------------------------------------
    # QVC
    # ------------------------------------------------------------------------

    def build_qvc!(assignment, variation, actor)
      send("build_qvc_#{variation}!", assignment, actor)
    end

    def build_qvc_scheduled!(assignment, actor)
      create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number: 1, scheduled_by: actor)
    end

    def build_qvc_re_medical!(assignment, actor)
      qvc_attempt(assignment, actor, attempt_number: 1, outcome_code: 're_medical', days_ago: 1)
    end

    def build_qvc_approved!(assignment, actor)
      qvc_attempt(assignment, actor, attempt_number: 1, outcome_code: 're_medical', days_ago: 5)
      qvc_attempt(assignment, actor, attempt_number: 2, outcome_code: 'approved', days_ago: 1)
    end

    def build_qvc_rejected!(assignment, actor)
      qvc_attempt(assignment, actor, attempt_number: 1, outcome_code: 'rejected', days_ago: 1)
    end

    def build_qvc_no_show!(assignment, actor)
      create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number: 1, scheduled_by: actor,
                                     no_show: true, outcome_recorded_at: 1.day.ago, outcome_recorded_by: actor)
    end

    def qvc_attempt(assignment, actor, attempt_number:, outcome_code:, days_ago:)
      create(:candidate_qvc_attempt, candidate_assignment: assignment, attempt_number:, scheduled_by: actor,
                                     outcome_code:, outcome_recorded_at: days_ago.days.ago, outcome_recorded_by: actor)
    end

    # ------------------------------------------------------------------------
    # Visa / protection / flight / payment
    # ------------------------------------------------------------------------

    def build_visa!(assignment, variation, actor)
      history = stage_history_for(assignment, 'visa_issued_or_rejected')
      send("build_visa_#{variation}!", assignment, actor, history)
    end

    def build_visa_issued!(assignment, actor, history)
      create(:candidate_visa_decision, candidate_assignment: assignment, candidate_stage_history: history,
                                       recorded_by: actor, outcome_code: 'issued', decision_date: 1.day.ago.to_date)
    end

    def build_visa_rejected!(assignment, actor, history)
      create(:candidate_visa_decision, candidate_assignment: assignment, candidate_stage_history: history,
                                       recorded_by: actor, outcome_code: 'rejected',
                                       rejection_reason_code: 'embassy_rejection', decision_date: 1.day.ago.to_date)
    end

    def build_protection!(assignment, variation, actor)
      send("build_protection_#{variation}!", assignment, actor)
    end

    def build_protection_appeared_only!(assignment, actor)
      create(:candidate_protection_record, candidate_assignment: assignment, appeared_on: 3.days.ago.to_date,
                                           appeared_recorded_at: 3.days.ago, appeared_recorded_by: actor)
    end

    def build_protection_ready_to_fly!(assignment, actor)
      create(:candidate_protection_record, candidate_assignment: assignment, appeared_on: 10.days.ago.to_date,
                                           appeared_recorded_at: 10.days.ago, appeared_recorded_by: actor,
                                           protected_on: 5.days.ago.to_date, ready_to_fly_at: 5.days.ago,
                                           ready_recorded_by: actor)
    end

    def build_flight!(assignment, variation, actor)
      history = stage_history_for(assignment, 'flight_details_uploaded')
      send("build_flight_#{variation}!", assignment, actor, history)
    end

    def build_flight_scheduled!(assignment, actor, history)
      create(:candidate_flight_detail, candidate_assignment: assignment, candidate_stage_history: history,
                                       recorded_by: actor, flight_departure_at: 5.days.from_now)
    end

    def build_flight_mobilized!(assignment, actor, history)
      mobilized_history = stage_history_for(assignment, 'mobilized')
      create(:candidate_flight_detail, candidate_assignment: assignment, candidate_stage_history: history,
                                       recorded_by: actor, flight_departure_at: 2.days.ago,
                                       mobilized_on: 1.day.ago.to_date, mobilized_stage_history: mobilized_history,
                                       mobilized_recorded_by: actor)
    end

    # A profile's own stage-history walk (build_stage_history!) may have already created a row
    # landing on this exact stage -- the (assignment, to_workflow_stage) pair is unique, so reuse
    # it instead of colliding with a second insert for the same transition.
    def stage_history_for(assignment, stage_code)
      assignment.candidate_stage_histories.joins(:to_workflow_stage)
                .find_by(workflow_stages: { code: stage_code }) ||
        create(:candidate_stage_history, candidate_assignment: assignment,
                                         to_workflow_stage: WorkflowStage.find_by!(code: stage_code))
    end

    def build_payment!(assignment, variation, actor)
      send("build_payment_#{variation}!", assignment, actor)
    end

    def build_payment_checkout_pending!(assignment, actor)
      create(:payment, candidate_assignment: assignment, recorded_by: actor, status_code: 'checkout_pending',
                       paid_at: nil, checkout_url: 'https://mock-payments.example.test/checkout?orderid=QA-SEED',
                       checkout_expires_at: 1.hour.from_now)
    end

    def build_payment_failed!(assignment, actor)
      create(:payment, candidate_assignment: assignment, recorded_by: actor, status_code: 'failed', paid_at: nil)
    end

    def build_payment_cancelled!(assignment, actor)
      create(:payment, candidate_assignment: assignment, recorded_by: actor, status_code: 'cancelled', paid_at: nil)
    end

    def build_payment_paid!(assignment, actor)
      payment = create(:payment, candidate_assignment: assignment, recorded_by: actor, status_code: 'paid',
                                 paid_at: 2.days.ago, external_reference: "QA-REF-#{SecureRandom.hex(4).upcase}")
      create(:payment_event, payment:, candidate_assignment: assignment, event_type: 'payment_succeeded',
                             occurred_at: 2.days.ago, processed_at: 2.days.ago)
      payment
    end

    # ------------------------------------------------------------------------
    # AI calls
    # ------------------------------------------------------------------------

    def build_ai_call!(candidate, assignment, spec, actor)
      call = create_ai_call(candidate, assignment, spec)
      apply_manual_review!(call, spec, actor) if spec[:needs_manual_review]
      attach_transcript(call, spec)
      call
    end

    def create_ai_call(candidate, assignment, spec)
      call_reason = spec[:call_reason] || 'general_helpline'
      create(:candidate_ai_call, :completed, candidate:, candidate_assignment: assignment, call_reason:,
                                             direction: spec.fetch(:direction),
                                             verification_status: verification_status_for(spec),
                                             outcome: spec[:outcome], outcome_reason: spec[:outcome_reason],
                                             workflow_stage_code: workflow_stage_code_for(call_reason, assignment))
    end

    def workflow_stage_code_for(call_reason, assignment)
      assignment.current_workflow_stage.code if call_reason == 'workflow_stage_notification'
    end

    def verification_status_for(spec)
      spec[:verification] || (spec.fetch(:direction) == 'inbound' ? 'verified' : 'not_applicable')
    end

    def apply_manual_review!(call, spec, actor)
      call.update!(outcome: nil, outcome_reason: 'needs_manual_review')
      resolve_manual_review!(call, actor) if spec[:resolve]
    end

    def attach_transcript(call, spec)
      return unless spec[:direction] == 'inbound' || spec[:outcome]

      create(:candidate_ai_call_transcript, candidate_ai_call: call)
    end

    def resolve_manual_review!(call, actor)
      AiCalls::ResolveManualReviewService.call(
        candidate_ai_call: call, actor:, outcome: 'answered', outcome_reason: 'resolved',
        request_id: SecureRandom.uuid, notes: 'Reviewed transcript -- candidate confirmed mobilization date.'
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
