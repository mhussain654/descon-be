# frozen_string_literal: true

module FileUploadHelper
  def fixture_upload(name, content_type)
    Rack::Test::UploadedFile.new(
      Rails.root.join('spec/fixtures/files', name),
      content_type,
      original_filename: name
    )
  end
end

RSpec.configure do |config|
  config.include FileUploadHelper
end
