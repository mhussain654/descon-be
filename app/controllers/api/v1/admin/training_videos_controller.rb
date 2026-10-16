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
          blob = ::ActiveStorage::Blob.find_signed(attributes.fetch(:file))
          return render_api_error(ValidationError.new(field: 'file', message: t('api.training_videos.invalid_file'))) unless blob
          unless blob.metadata['training_video_owner_id'].to_s == current_user.id.to_s &&
                 blob.created_at > 2.hours.ago && !blob.attachments.exists? &&
                 blob.content_type == 'video/mp4' && blob.byte_size.between?(1, ::TrainingVideo::MAX_BYTES) &&
                 blob.service.exist?(blob.key) &&
                 blob.download_chunk(0..11).byteslice(4, 4) == 'ftyp'
            return render_api_error(ValidationError.new(field: 'file', message: t('api.training_videos.invalid_file')))
          end
          video = ::TrainingVideo.new(attributes.except(:file).merge(created_by: current_user))
          video.file.attach(blob)
          video.save!
          audit!(video, 'training_video_created')
          render_success(data: serialize(video), status: :created)
        end

        def upload
          authorize ::TrainingVideo, :create?, policy_class: ::Admin::TrainingVideoPolicy
          input = params.expect(training_video_upload: %i[filename byte_size content_type checksum])
          size = Integer(input.fetch(:byte_size), exception: false)
          unless size&.between?(1, ::TrainingVideo::MAX_BYTES) && input[:content_type] == 'video/mp4' &&
                 input[:checksum].to_s.match?(/\A[A-Za-z0-9+\/]{22}==\z/)
            return render_api_error(ValidationError.new(field: 'file', message: t('api.training_videos.invalid_file')))
          end
          blob = ::ActiveStorage::Blob.create_before_direct_upload!(
            filename: input.fetch(:filename), byte_size: size, checksum: input.fetch(:checksum),
            content_type: 'video/mp4', metadata: { training_video_owner_id: current_user.id }
          )
          render_success(data: { signed_id: blob.signed_id(expires_in: 2.hours),
                                 upload_url: blob.service_url_for_direct_upload(expires_in: 15.minutes),
                                 upload_headers: blob.service_headers_for_direct_upload }, status: :created)
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
