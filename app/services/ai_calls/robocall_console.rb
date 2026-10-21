# frozen_string_literal: true

module AiCalls
  # What the `ai_calls:robocall:*` rake tasks print: a key/balance check, one
  # real (charged) test call, and one call's status. Each method returns the
  # lines to print, so the rake file stays a thin wrapper. Never returns the
  # api key.
  class RobocallConsole
    STATUS_NAMES = {
      1 => 'initiated', 2 => 'answered', 3 => 'congestion', 4 => 'busy', 5 => 'no answer', 6 => 'hangup',
      8 => 'pushed to SIP'
    }.freeze

    def initialize(adapter: Providers::RobocallAdapter.new)
      @adapter = adapter
    end

    # Raises AiCallProviderUnavailableError when no api key is configured.
    def check
      key = @adapter.verify_key
      balance = @adapter.check_balance['data'] || {}
      ["Key check: valid=#{key['valid'].inspect} message=#{key['message'].inspect}",
       "Balance: #{balance['balance'].inspect} (call rate: #{balance['call_rate'].inspect})"]
    end

    def place_call(voice_id:, number:)
      result = @adapter.initiate_call(voice_id:, to_number: number)
      ["Call placed. call_id=#{result.call_id.inspect}"]
    end

    # Looking at RoboCall's real answer for several numbers; places real calls.
    def place_multiple(voice_id:, numbers:)
      body = @adapter.initiate_multiple_calls_raw(voice_id:, to_numbers: numbers)
      ["Response: #{JSON.generate(body)}"]
    end

    def status(call_id:)
      status = @adapter.fetch_call(call_id:)
      name = STATUS_NAMES.fetch(status.status_code, 'unknown')
      ["status_code=#{status.status_code.inspect} (#{name}) dtmf=#{status.dtmf.inspect}"]
    end
  end
end
