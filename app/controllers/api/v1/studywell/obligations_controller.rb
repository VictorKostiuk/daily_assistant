module Api
  module V1
    module Studywell
      class ObligationsController < Api::V1::BaseController
        PAGE_SIZE = 100

        def index
          course = find_course!
          page = InputValidator.page(request.query_parameters)
          status = InputValidator.obligation_list_status(request.query_parameters)
          scope = course.obligations.order(:id)
          scope = scope.where(status: status) unless status == "all"

          records = scope.offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
          has_more = records.size > PAGE_SIZE
          records = records.first(PAGE_SIZE)

          render json: {
            items: records.map { |obligation| obligation_json(obligation) },
            next_page: has_more ? page + 1 : nil
          }
        end

        def show
          render json: obligation_json(find_obligation!)
        end

        def create
          course = find_course!
          attrs = InputValidator.obligation_create(request.request_parameters)
          obligation = course.obligations.build(attrs)
          obligation.user = current_api_user
          if obligation.save
            render json: obligation_json(obligation), status: :created
          else
            render_validation_error(obligation.errors.messages)
          end
        end

        def update
          obligation = find_obligation!
          attrs = InputValidator.obligation_patch(request.request_parameters, kind: obligation.kind)
          apply_obligation_attrs!(obligation, attrs)
          if obligation.save
            render json: obligation_json(obligation)
          else
            render_validation_error(obligation.errors.messages)
          end
        end

        def destroy
          lock_version = InputValidator.require_only_lock_version(request.request_parameters)
          obligation = find_obligation!
          return render_conflict if obligation.lock_version != lock_version

          obligation.destroy!
          head :no_content
        end

        private

        def find_course!
          current_api_user.studywell_courses.find_by(id: params[:course_id]) || (raise ActiveRecord::RecordNotFound)
        end

        def find_obligation!
          current_api_user.studywell_obligations.find_by(id: params[:id]) || (raise ActiveRecord::RecordNotFound)
        end

        def apply_obligation_attrs!(obligation, attrs)
          lock_version = attrs.delete("lock_version")
          status = attrs.delete("status")
          obligation.lock_version = lock_version
          obligation.assign_attributes(attrs)
          return if status.nil?

          if status == "done"
            obligation.completed_at = Time.current if obligation.open?
            obligation.status = :done
          else
            obligation.completed_at = nil if obligation.done?
            obligation.status = :open
          end
        end

        def obligation_json(obligation)
          {
            id: obligation.id,
            course_id: obligation.course_id,
            kind: obligation.kind,
            title: obligation.title,
            due_at: obligation.due_at&.iso8601,
            starts_at: obligation.starts_at&.iso8601,
            ends_at: obligation.ends_at&.iso8601,
            importance: obligation.importance,
            estimated_minutes: obligation.estimated_minutes,
            progress_percent: obligation.progress_percent,
            notes: obligation.notes,
            status: obligation.status,
            completed_at: obligation.completed_at&.iso8601,
            lock_version: obligation.lock_version,
            remaining_minutes: obligation.remaining_minutes
          }
        end
      end
    end
  end
end
