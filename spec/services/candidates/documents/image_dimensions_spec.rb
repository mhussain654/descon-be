# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Candidates::Documents::ImageDimensions do
  def fixture(name) = Rails.root.join('spec/fixtures/files', name).open('rb')

  describe '.read' do
    it 'reads the width and height of a PNG and a JPEG, leaving the file at its start' do
      %w[document_photo.png document_photo.jpg].zip(%w[image/png image/jpeg]).each do |name, content_type|
        file = fixture(name)
        expect(described_class.read(file, content_type)).to eq([600, 800])
        expect(file.pos).to eq(0)
      end
    end

    it 'gives nil for a PDF, an unknown type, or a file whose header is not a PNG or JPEG' do
      expect(described_class.read(fixture('test.pdf'), 'application/pdf')).to be_nil
      expect(described_class.read(fixture('document_photo.png'), 'image/webp')).to be_nil
      expect(described_class.read(StringIO.new('not an image'), 'image/png')).to be_nil
      expect(described_class.read(StringIO.new('not an image'), 'image/jpeg')).to be_nil
    end

    it 'gives nil for a JPEG that ends before its size, or holds a broken marker' do
      expect(described_class.read(StringIO.new("\xFF\xD8\xFF\xE0".b), 'image/jpeg')).to be_nil
      expect(described_class.read(StringIO.new("\xFF\xD8\x00".b), 'image/jpeg')).to be_nil
      expect(described_class.read(StringIO.new("\xFF\xD8\xFF\xD9".b), 'image/jpeg')).to be_nil
      expect(described_class.read(StringIO.new("\xFF\xD8\xFF\xC0\x00\x11\x08\x01".b), 'image/jpeg')).to be_nil
    end

    it 'skips standalone JPEG markers before the frame' do
      jpeg = "\xFF\xD8\xFF\xD0\xFF\xFF\xC0\x00\x11\x08".b + [700, 900].pack('nn') + "\x03".b
      expect(described_class.read(StringIO.new(jpeg), 'image/jpeg')).to eq([900, 700])
    end
  end

  describe '.too_small?' do
    it 'is true only when a readable side is under 500 pixels' do
      expect(described_class.too_small?(fixture('small_photo.png'), 'image/png')).to be(true)
      expect(described_class.too_small?(fixture('small_photo.jpg'), 'image/jpeg')).to be(true)
      expect(described_class.too_small?(fixture('document_photo.jpg'), 'image/jpeg')).to be(false)
      expect(described_class.too_small?(fixture('test.pdf'), 'application/pdf')).to be(false)
    end
  end
end
