# frozen_string_literal: true

module Api
  module V1
    module Candidate
      class TrainingVideosController < ProtectedController
        before_action :configure_storage_url
        def index
          authorize ::TrainingVideo, policy_class: ::Candidates::TrainingVideoPolicy
          response.set_header('Cache-Control', 'private, no-store')
          videos = ::TrainingVideo.published.includes(file_attachment: :blob).ordered.limit(100)
          render_success(data: videos.map { |video| ::TrainingVideos::VideoSerializer.new(video, include_access: true).as_json })
        end

        private

        def configure_storage_url
          ::ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
        end
      end
    end
  end
end
