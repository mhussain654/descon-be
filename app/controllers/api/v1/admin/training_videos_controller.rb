# frozen_string_literal: true

module Api
  module V1
    module Admin
      class TrainingVideosController < ProtectedStaffController
        before_action :configure_storage_url
        def index
          authorize ::TrainingVideo, policy_class: ::Admin::TrainingVideoPolicy
          render_success(data: videos.map { |video| serialize(video) })
        end

        def create
          authorize ::TrainingVideo, policy_class: ::Admin::TrainingVideoPolicy
          video = ::TrainingVideos::CreateService.call(creator: current_user, attributes: attributes.except(:file),
                                                       signed_blob_id: attributes.fetch(:file))
          audit!(video, 'training_video_created')
          render_success(data: serialize(video), status: :created)
        end

        def upload
          authorize ::TrainingVideo, :create?, policy_class: ::Admin::TrainingVideoPolicy
          ticket = ::TrainingVideos::DirectUploadTicketService.call(owner: current_user, **upload_params)
          render_success(data: ticket, status: :created)
        end

        def update
          video = ::TrainingVideo.find(params.expect(:id))
          authorize video, policy_class: ::Admin::TrainingVideoPolicy
          video.update!(attributes.except(:file))
          audit!(video, 'training_video_updated')
          render_success(data: serialize(video))
        end

        def destroy
          video = ::TrainingVideo.find(params.expect(:id))
          authorize video, policy_class: ::Admin::TrainingVideoPolicy
          video.destroy!
          audit!(video, 'training_video_deleted')
          head :no_content
        end

        private

        def configure_storage_url
          ::ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.port }
        end

        def videos
          policy_scope(::TrainingVideo, policy_scope_class: ::Admin::TrainingVideoPolicy::Scope)
            .includes(file_attachment: :blob).ordered.limit(100)
        end

        def upload_params
          params.expect(training_video_upload: %i[filename byte_size content_type checksum]).to_h.symbolize_keys
        end

        def attributes
          params.expect(training_video: %i[title_en title_ur description_en description_ur position published file])
        end

        def serialize(video)
          ::TrainingVideos::VideoSerializer.new(video, include_access: true).as_json
        end

        def audit!(video, action)
          ::AuditEvent.create!(actor: current_user, entity_type: 'TrainingVideo', entity_id: video.id,
                               action_code: action, request_id: request.request_id, occurred_at: Time.current,
                               metadata: { video_id: video.id })
        end
      end
    end
  end
end
