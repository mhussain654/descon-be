# frozen_string_literal: true

namespace :ai_calls do
  namespace :robocall do
    desc 'Checks the RoboCall api key and prints the remaining balance. Read-only; prints no secrets.'
    task check: :environment do
      run_robocall_console(&:check)
    end

    desc 'Places ONE real, charged RoboCall call: bin/rails "ai_calls:robocall:call[VOICE_ID,923001234567]". ' \
         'Prints the provider call id. Records nothing in the database.'
    task :call, %i[voice_id number] => :environment do |_task, args|
      if args[:voice_id].blank? || args[:number].blank?
        abort('Usage: bin/rails "ai_calls:robocall:call[VOICE_ID,923001234567]"')
      end

      run_robocall_console { |console| console.place_call(voice_id: args[:voice_id], number: args[:number]) }
    end

    desc 'Prints the status and key press of one RoboCall call: bin/rails "ai_calls:robocall:status[CALL_ID]".'
    task :status, [:call_id] => :environment do |_task, args|
      abort('Usage: bin/rails "ai_calls:robocall:status[CALL_ID]"') if args[:call_id].blank?

      run_robocall_console { |console| console.status(call_id: args[:call_id]) }
    end
  end
end

# Exploratory: shows RoboCall's real response to a multiple-calls request before anything depends on it.
namespace :ai_calls do
  namespace :robocall do
    desc 'Places REAL, charged calls to several numbers in one request to see RoboCall\'s response: ' \
         'bin/rails "ai_calls:robocall:multiple[VOICE_ID,923001234567 923007654321]" (numbers separated by spaces).'
    task :multiple, %i[voice_id numbers] => :environment do |_task, args|
      numbers = args[:numbers].to_s.split
      abort('Usage: bin/rails "ai_calls:robocall:multiple[VOICE_ID,923001234567 923007654321]"') if
        args[:voice_id].blank? || numbers.empty?

      run_robocall_console { |console| console.place_multiple(voice_id: args[:voice_id], numbers:) }
    end
  end
end

def run_robocall_console
  puts yield(AiCalls::RobocallConsole.new)
rescue AiCallProviderUnavailableError
  abort('RoboCall api key is missing from the encrypted credentials (robocall.<env>.api_key).')
rescue AiCallProviderRequestError => e
  abort("RoboCall request failed: #{e.message}")
end
