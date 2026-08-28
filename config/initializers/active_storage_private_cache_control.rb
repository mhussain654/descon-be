# frozen_string_literal: true

module ActiveStoragePrivateCacheControl
  module BlobProxy
    def show
      apply_private_cache_headers
      return send_blob_byte_range_data(@blob, request.headers['Range']) if request.headers['Range'].present?

      prepare_blob_stream_headers
      send_blob_stream(@blob, disposition: params[:disposition])
    end

    private

    def apply_private_cache_headers
      response.headers['Cache-Control'] = 'no-store, private'
    end

    def prepare_blob_stream_headers
      response.headers['Accept-Ranges'] = 'bytes'
      response.headers['Content-Length'] = @blob.byte_size.to_s
    end
  end

  module RepresentationProxy
    def show
      response.headers['Cache-Control'] = 'no-store, private'
      send_blob_stream(@representation, disposition: params[:disposition])
    end
  end
end

Rails.application.config.to_prepare do
  ActiveStorage::Blobs::ProxyController.prepend(ActiveStoragePrivateCacheControl::BlobProxy) unless
    ActiveStorage::Blobs::ProxyController < ActiveStoragePrivateCacheControl::BlobProxy
  ActiveStorage::Representations::ProxyController.prepend(ActiveStoragePrivateCacheControl::RepresentationProxy) unless
    ActiveStorage::Representations::ProxyController < ActiveStoragePrivateCacheControl::RepresentationProxy
end
