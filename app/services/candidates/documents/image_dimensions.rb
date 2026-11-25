# frozen_string_literal: true

module Candidates
  module Documents
    # Reads a JPEG or PNG's width and height from its header, without an image
    # library, so a document photo too small to read can be refused before it
    # is stored. PDFs (and anything unreadable) give nil and are never refused
    # here.
    class ImageDimensions
      # The smallest width and height a document photo may have (client rule).
      MINIMUM_SIDE = 500
      PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
      # JPEG start-of-frame markers, which carry the image size (not DHT 0xC4, JPG 0xC8 or DAC 0xCC).
      JPEG_FRAME_MARKERS = ((0xC0..0xCF).to_a - [0xC4, 0xC8, 0xCC]).freeze
      # Markers that stand alone, with no length after them.
      JPEG_STANDALONE_MARKERS = [0x01, *0xD0..0xD7].freeze

      # [width, height], or nil when the size can't be read.
      def self.read(io, content_type)
        io.rewind
        case content_type
        when 'image/png' then png(io)
        when 'image/jpeg' then jpeg(io)
        end
      rescue EOFError, IOError, TypeError, NoMethodError
        nil
      ensure
        io.rewind
      end

      # True only when the size could be read and a side is below MINIMUM_SIDE.
      def self.too_small?(io, content_type)
        size = read(io, content_type)
        size.present? && size.min < MINIMUM_SIDE
      end

      def self.png(io)
        header = io.read(24).to_s.b
        return unless header.bytesize == 24 && header.start_with?(PNG_SIGNATURE) && header[12, 4] == 'IHDR'

        header[16, 8].unpack('NN')
      end

      def self.jpeg(io)
        return unless io.read(2).to_s.b == "\xFF\xD8".b

        loop do
          marker = next_jpeg_marker(io) or return nil
          next if JPEG_STANDALONE_MARKERS.include?(marker)
          return nil if marker == 0xD9 # end of image

          length = io.read(2).to_s.unpack1('n') or return nil
          return jpeg_frame_size(io) if JPEG_FRAME_MARKERS.include?(marker)

          io.seek(length - 2, IO::SEEK_CUR)
        end
      end

      def self.next_jpeg_marker(io)
        byte = io.readbyte
        return nil unless byte == 0xFF

        byte = io.readbyte while byte == 0xFF
        byte
      end

      def self.jpeg_frame_size(io)
        frame = io.read(5).to_s.b
        return unless frame.bytesize == 5

        height, width = frame[1, 4].unpack('nn')
        [width, height]
      end

      private_class_method :png, :jpeg, :next_jpeg_marker, :jpeg_frame_size
    end
  end
end
