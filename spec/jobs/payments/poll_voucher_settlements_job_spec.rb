# frozen_string_literal: true

require 'rails_helper'
require 'fugit' # Solid Queue's schedule parser, loaded here only to read config/recurring.yml

RSpec.describe Payments::PollVoucherSettlementsJob do
  before do
    allow(Payments::SettleVouchersService).to receive(:call)
    allow(Payments::ExpireVouchersService).to receive(:call)
  end

  it "checks today's payments by default, then closes expired vouchers" do
    described_class.perform_now

    expect(Payments::SettleVouchersService).to have_received(:call).with(days_ago: 0).ordered
    expect(Payments::ExpireVouchersService).to have_received(:call).ordered
  end

  it "checks yesterday's payments when scheduled for yesterday" do
    described_class.perform_now('yesterday')

    expect(Payments::SettleVouchersService).to have_received(:call).with(days_ago: 1)
  end

  it 'skips the run, without failing, when KuickPay is unavailable' do
    allow(Payments::SettleVouchersService).to receive(:call).and_raise(PaymentCheckoutUnavailableError)

    expect { described_class.perform_now }.not_to raise_error
    expect(Payments::ExpireVouchersService).not_to have_received(:call)
  end

  # KuickPay allows only five Bulk Inquiry calls a day, and each run makes one.
  describe 'schedule (config/recurring.yml)' do
    let(:tasks) do
      YAML.load_file(Rails.root.join('config/recurring.yml'), aliases: true).fetch('production')
          .values.select { |task| task['class'] == described_class.name }
    end

    def karachi_hours_in_a_day(task)
      cron = Fugit.parse_cronish(task.fetch('schedule'))
      start = Time.find_zone!('Asia/Karachi').parse('2026-11-14 00:00')
      times = []
      time = cron.next_time(start - 1).to_t
      while time < start + 1.day
        times << time.in_time_zone('Asia/Karachi').hour
        time = cron.next_time(time).to_t
      end
      times
    end

    it 'runs five times a day in Pakistan time: yesterday at 10:00, today at 13:00, 16:00, 19:00 and 23:00' do
      schedule = tasks.to_h { |task| [task.fetch('args'), karachi_hours_in_a_day(task)] }

      expect(schedule).to eq(%w[yesterday] => [10], %w[today] => [13, 16, 19, 23])
    end
  end
end
