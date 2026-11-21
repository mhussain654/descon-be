# frozen_string_literal: true

module DocumentOcr
  # OCR read the page but found no issue or expiry date. Carries what the text
  # looked like (IdentityMarkers), so a photo that isn't an ID at all can be
  # told from a real one whose dates were hard to read.
  class NoDatesError < PermanentError
    attr_reader :identity

    def initialize(message = nil, identity: nil)
      super(message)
      @identity = identity
    end
  end
end
