# frozen_string_literal: true

module Sms
  # Internal configuration error, not an API-facing BaseError -- if this is
  # ever raised in production it means deployment is missing SMS_PROVIDER,
  # which should surface as a 500 (via ApplicationController's generic
  # StandardError rescue) and get investigated, not be papered over by
  # silently falling back to the test provider.
  class ProviderNotConfiguredError < StandardError; end
end
