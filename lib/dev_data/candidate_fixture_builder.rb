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

    # One optional builder per Profile field -- looping over this table instead of a chain of
    # `if profile.x` calls keeps dispatch data-driven rather than branchy.
    OPTIONAL_BUILDERS = {
      documents: :build_documents!, qvc: :build_qvc!, visa: :build_visa!, protection: :build_protection!,
      flight: :build_flight!, payment: :build_payment!
    }.freeze

    # Plausible-looking full names for demo/QA candidates -- picked so a client
    # demo shows a real-looking roster instead of "QA Seed Candidate 01
    # (documents_pending)". Purely synthetic (no real person), one per
    # QaDataSeeder::Profile, in order. Which rows are QA-seeded is tracked via
    # `created_by` (always a qa-*@descon.local user -- see
    # QaDataSeeder#actor_for), never by name, so this list can read naturally
    # without doubling as a database marker.
    CANDIDATE_NAMES = [
      'Muhammad Usman Sheikh', 'Ahmed Raza Khan', 'Bilal Hussain', 'Imran Ali Qureshi',
      'Fahad Mehmood', 'Waqas Ahmed', 'Zeeshan Iqbal', 'Kamran Yousaf', 'Adnan Malik',
      'Shahid Nawaz', 'Rizwan Shahzad', 'Naveed Anjum', 'Tariq Mahmood', 'Faisal Rasheed',
      'Asif Jameel', 'Junaid Aslam', 'Sajjad Haider', 'Arslan Hameed', 'Noman Saeed',
      'Irfan Bashir', 'Hamza Farooq', 'Salman Abbas', 'Yasir Latif', 'Danish Aziz',
      'Umar Farooq Chaudhry', 'Ali Raza Baloch'
    ].freeze

    def build(profile:, index:, actor:, reference:)
      candidate = build_candidate(profile, index, actor)
      assignment = build_assignment(candidate, actor, reference, profile)

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
      create(:candidate, full_name: CANDIDATE_NAMES.fetch(index), created_by: actor,
                         skip_consent: profile.consent_accepted == false)
    end

    def build_assignment(candidate, actor, reference, profile)
      create(:candidate_assignment, candidate:, created_by: actor, country: country_for(profile, reference),
                                    project: reference.fetch(:projects).sample, craft: reference.fetch(:crafts).sample)
    end

    # A random country whose mobilization process actually has every stage this profile's data
    # implies (e.g. QVC or flight data only make sense for a Qatar candidate).
    def country_for(profile, reference)
      required_codes = [profile.stage]
      required_codes << 'qvc_appointment_booked' if profile.qvc
      required_codes << 'flight_details_uploaded' if profile.flight
      reference.fetch(:countries).select do |country|
        process = MobilizationProcess.resolve_for(country)
        process && required_codes.all? { |code| process.includes_stage_code?(code) }
      end.sample || raise("No active mobilization process includes #{required_codes.join(', ')}")
    end

    # Walks the assignment's own process from `registered` up to `target_code`, leaving a
    # realistic CandidateStageHistory trail behind -- not just the assignment landing directly on
    # the final stage -- so the per-candidate workflow-history admin tab has something to show.
    def build_stage_history!(assignment, target_code, actor)
      stage_codes = assignment.mobilization_process.stages.includes(:workflow_stage).map(&:code)
      target_index = stage_codes.index(target_code)
      return if target_index.zero?

      base_time = 30.days.ago
      (1..target_index).each { |i| create_stage_history_step(assignment, stage_codes, i, actor, base_time) }
      assignment.update!(current_workflow_stage: WorkflowStage.find_by!(code: target_code))
      # Mirrors CandidateWorkflows::TransitionService#apply_transition!, which real transitions
      # always update together -- built directly here (not via TransitionService) since a seed
      # profile jumps straight to its target stage rather than walking prerequisite checks.
      assignment.candidate.update!(status_code: target_code)
    end

    def create_stage_history_step(assignment, stage_codes, index, actor, base_time)
      history = create(
        :candidate_stage_history,
        candidate_assignment: assignment, actor:, occurred_at: base_time + (index * 2).days,
        from_workflow_stage: WorkflowStage.find_by!(code: stage_codes[index - 1]),
        to_workflow_stage: WorkflowStage.find_by!(code: stage_codes[index])
      )
      record_fit_medical_result!(assignment, history, actor)
    end

    # Passing the process's medical-outcome stage means the candidate was found fit.
    def record_fit_medical_result!(assignment, history, actor)
      return unless history.to_mobilization_process_stage.action_type == 'medical_outcome'

      create(:candidate_medical_result, candidate_assignment: assignment, candidate_stage_history: history,
                                        recorded_by: actor, outcome_code: 'fit',
                                        result_date: history.occurred_at.to_date)
    end

    # ------------------------------------------------------------------------
    # Documents
    # ------------------------------------------------------------------------

    # Documents for the assignment's own checklist (its country, project and craft decide it).
    def build_documents!(assignment, variation, actor)
      @requirements_by_type = Candidates::Documents::RequirementResolver
                              .call(candidate: assignment.candidate, assignment:)
                              .select(&:required).index_by(&:document_type)
      @document_types = @requirements_by_type.keys
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
      create(:candidate_document, **attrs, files: document_files(@requirements_by_type.fetch(type)))
    end

    # A realistic file set for the requirement: front + back images, passport page 1 + page 2,
    # two certificates, or a single PDF.
    def document_files(requirement)
      sides = requirement.allowed_side_codes
      layout = if sides.include?('front') then [%w[front image/jpeg], %w[back image/jpeg]]
               elsif sides.include?('page_1') then [%w[page_1 image/jpeg], %w[page_2 image/jpeg]]
               elsif sides.include?('certificate') then [%w[certificate application/pdf]] * 2
               else [[nil, requirement.accepted_content_types.first]]
               end
      layout.each_with_index.map { |(side_code, content_type), index| fixture_file(side_code, content_type, index + 1) }
    end

    def fixture_file(side_code, content_type, position)
      name = content_type == 'application/pdf' ? 'test.pdf' : 'test.jpg'
      FactoryBot.build(:candidate_document_file, side_code:, position:, content_type:,
                                                 original_filename: name).tap do |file|
        file.file.attach(io: Rails.root.join('spec/fixtures/files', name).open, filename: name, content_type:)
      end
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
      decision = create(:candidate_visa_decision, candidate_assignment: assignment, candidate_stage_history: history,
                                                  recorded_by: actor, outcome_code: 'issued',
                                                  decision_date: 1.day.ago.to_date)
      # Without a real attached file, the candidate app's visa-copy download action has
      # nothing to serve -- an issued-visa demo candidate would show "Verified"/"Issued"
      # everywhere but the actual download button/link would never appear.
      decision.visa_copy.attach(
        io: Rails.root.join('spec/fixtures/files/test.pdf').open,
        filename: 'visa_copy.pdf',
        content_type: 'application/pdf'
      )
      decision
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
      call = create_ai_call(candidate, assignment, spec, actor)
      apply_manual_review!(call, spec, actor) if spec[:needs_manual_review]
      attach_transcript(call, spec)
      call
    end

    # Passes `communication:` explicitly -- :candidate_ai_call's factory default
    # (`association :communication`) would otherwise build its own throwaway Communication,
    # which itself defaults a brand-new bare :candidate_assignment (and :candidate) rather than
    # reusing this one, leaving an orphaned extra candidate behind for every profile with an
    # ai_call spec.
    def create_ai_call(candidate, assignment, spec, actor)
      call_reason = spec[:call_reason] || 'general_helpline'
      communication = create(:communication, candidate_assignment: assignment, initiated_by: actor,
                                             channel_code: 'ai_voice_call', direction_code: spec.fetch(:direction))
      create(:candidate_ai_call, :completed, communication:, candidate:, candidate_assignment: assignment, call_reason:,
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
