module Api
  module V1
    class RemindersController < BaseController
      PAGE_SIZE = 100

      def index
        page = InputValidator.page(request.query_parameters)
        records = current_api_user.reminders.order(:scheduled_at, :id)
          .offset((page - 1) * PAGE_SIZE)
          .limit(PAGE_SIZE + 1)
          .to_a
        has_more = records.size > PAGE_SIZE
        records = records.first(PAGE_SIZE)

        render json: {
          items: records.map { |reminder| reminder_json(reminder) },
          next_page: has_more ? page + 1 : nil
        }
      end

      def show
        render json: reminder_json(find_reminder!)
      end

      def create
        attrs = InputValidator.reminder_create(request.request_parameters, time_zone: caller_time_zone)
        reminder = Reminders::Create.call(
          user: current_api_user,
          title: attrs["title"],
          scheduled_at: attrs["scheduled_at"],
          offset_minutes: attrs["offset_minutes"],
          source: :api,
          metadata: attrs["metadata"]
        )
        render json: reminder_json(reminder), status: :created
      end

      def update
        attrs = InputValidator.reminder_patch(request.request_parameters, time_zone: caller_time_zone)
        reminder = find_reminder!
        updates = attrs.except("metadata")
        updates[:metadata] = SourceMetadata.merge(reminder.metadata, attrs["metadata"]) if attrs.key?("metadata")
        updates[:updated_at] = Time.current

        changed = current_api_user.reminders.where(id: reminder.id, status: :pending).update_all(updates)
        if changed == 1
          render json: reminder_json(reminder.reload)
        else
          render_conflict
        end
      end

      def destroy
        changed = current_api_user.reminders.where(id: params[:id], status: :pending).update_all(
          status: Reminder.statuses[:cancelled],
          cancelled_at: Time.current,
          updated_at: Time.current
        )
        return head :no_content if changed == 1

        reminder = current_api_user.reminders.find_by(id: params[:id])
        return render_not_found if reminder.nil?
        return head :no_content if reminder.cancelled?

        render_conflict
      end

      private

      def find_reminder!
        current_api_user.reminders.find_by(id: params[:id]) || (raise ActiveRecord::RecordNotFound)
      end

      def reminder_json(reminder)
        source = SourceMetadata.load(reminder.metadata)
        {
          id: reminder.id,
          title: reminder.title,
          scheduled_at: reminder.scheduled_at.iso8601,
          offset_minutes: reminder.offset_minutes,
          time_zone: reminder.time_zone,
          status: reminder.status,
          source: reminder.source,
          context_type: source["context_type"],
          source_app: source["source_app"],
          source_entity_type: source["source_entity_type"],
          source_entity_id: source["source_entity_id"]
        }
      end
    end
  end
end
