module Api
  module V1
    module Studywell
      class CoursesController < Api::V1::BaseController
        PAGE_SIZE = 100

        def index
          page = InputValidator.page(request.query_parameters)
          include_archived = InputValidator.include_archived(request.query_parameters)
          scope = current_api_user.studywell_courses.order(:id)
          scope = scope.where(archived_at: nil) unless include_archived

          records = scope.offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
          has_more = records.size > PAGE_SIZE
          records = records.first(PAGE_SIZE)

          render json: {
            items: records.map { |course| course_json(course) },
            next_page: has_more ? page + 1 : nil
          }
        end

        def show
          render json: course_json(find_course!)
        end

        def create
          attrs = InputValidator.course_create(request.request_parameters)
          course = current_api_user.studywell_courses.build(attrs)
          if course.save
            render json: course_json(course), status: :created
          else
            render_validation_error(course.errors.messages)
          end
        end

        def update
          attrs = InputValidator.course_patch(request.request_parameters)
          course = find_course!
          apply_course_attrs!(course, attrs)
          if course.save
            render json: course_json(course)
          else
            render_validation_error(course.errors.messages)
          end
        end

        def destroy
          lock_version = InputValidator.require_only_lock_version(request.request_parameters)
          course = find_course!
          return render_conflict if course.lock_version != lock_version

          count = course.obligations.count
          if count.positive?
            return render_error(
              code: "conflict",
              message: "Conflict",
              status: :conflict,
              details: { "obligations_count" => count }
            )
          end

          course.destroy!
          head :no_content
        end

        private

        def find_course!
          current_api_user.studywell_courses.find_by(id: params[:id]) || (raise ActiveRecord::RecordNotFound)
        end

        def apply_course_attrs!(course, attrs)
          lock_version = attrs.delete("lock_version")
          archived = attrs.delete("archived")
          course.lock_version = lock_version
          course.assign_attributes(attrs)
          return if archived.nil?

          if archived
            course.archived_at ||= Time.current
          else
            course.archived_at = nil
          end
        end

        def course_json(course)
          {
            id: course.id,
            name: course.name,
            code: course.code,
            term_label: course.term_label,
            colour: course.colour,
            active_from: course.active_from&.iso8601,
            active_until: course.active_until&.iso8601,
            archived_at: course.archived_at&.iso8601,
            lock_version: course.lock_version
          }
        end
      end
    end
  end
end
