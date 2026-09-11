# frozen_string_literal: true

module AiCalls
  module Prompts
    class MissingDocumentsPrompt < ScenarioPrompt
      def self.call_reason = 'missing_documents'
    end
  end
end
