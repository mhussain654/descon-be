# frozen_string_literal: true

module TrainingVideos
  # Raised for any upload that is not an acceptable training video; the message is deliberately
  # generic so a failed check never reveals which rule it tripped.
  class InvalidFileError < ValidationError
    def initialize
      super(field: 'file', message: I18n.t('api.training_videos.invalid_file'))
    end
  end
end
