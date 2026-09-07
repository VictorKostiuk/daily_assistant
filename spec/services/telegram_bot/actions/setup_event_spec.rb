require "rails_helper"

RSpec.describe TelegramBot::Actions::SetupEvent do
  let(:telegram_api) { double("Telegram::Bot::Api", send_message: nil) }
  let(:bot) { instance_double(Telegram::Bot::Client, api: telegram_api) }

  def call_action(text, telegram_account, pending: nil)
    described_class.call(bot: bot, update: telegram_message(text, telegram_account), pending: pending)
  end

  it "asks for a description when the bare command is sent" do
    telegram_account = create(:telegram_account)
    create(:user_integration, user: telegram_account.user)

    call_action("/setup_event", telegram_account)

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/what should i schedule/i)))
  end

  it "asks the member to link Telegram first when there is no matching account" do
    unlinked = build_stubbed(:telegram_account)

    described_class.call(bot: bot, update: telegram_message("/setup_event", unlinked))

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/not linked/i)))
  end

  it "asks to connect Google when the user has no connected Google integration" do
    telegram_account = create(:telegram_account)

    call_action("/setup_event", telegram_account)

    expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/google is not connected/i)))
  end

  context "with a description and a connected Google account" do
    let(:telegram_account) { create(:telegram_account) }
    let(:event) do
      Integrations::OpenRouter::EventParsing::Event.new(
        title: "Dinner with Anna", description: nil, location: "Trattoria",
        starts_at: Time.zone.parse("2026-08-10 19:00"), ends_at: Time.zone.parse("2026-08-10 20:00"), all_day: false
      )
    end
    let(:created_event) { instance_double(Google::Apis::CalendarV3::Event, id: "gcal_event_x", html_link: "https://calendar.google.com/x") }
    # The user has no user_setting here, so CreateEvent selects "primary".
    let(:create_result) do
      Integrations::Google::CreateEvent::Result.new(provider_event: created_event, calendar_id: "primary")
    end

    before do
      create(:user_integration, user: telegram_account.user)
      allow(Integrations::OpenRouter::ParseEvent).to receive(:call).and_return(event)
      allow(Integrations::Google::CreateEvent).to receive(:call).and_return(create_result)
    end

    it "parses the description, creates the event, and confirms it" do
      call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)

      expect(Integrations::OpenRouter::ParseEvent).to have_received(:call).with(text: "dinner with Anna tomorrow at 19:00", time_zone: telegram_account.user.time_zone)
      expect(Integrations::Google::CreateEvent).to have_received(:call).with(user: telegram_account.user, event: event)
      expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/Dinner with Anna/)))
    end

    it "records a succeeded action execution" do
      expect {
        call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)
      }.to change { telegram_account.user.action_executions.succeeded.count }.by(1)
    end

    it "resumes a two-step conversation using the free-text follow-up" do
      pending = { command: "/setup_event", stage: "description" }

      call_action("dinner with Anna tomorrow at 19:00", telegram_account, pending: pending)

      expect(Integrations::OpenRouter::ParseEvent).to have_received(:call).with(text: "dinner with Anna tomorrow at 19:00", time_zone: telegram_account.user.time_zone)
    end

    it "reports a failure and records it when parsing fails" do
      allow(Integrations::OpenRouter::ParseEvent).to receive(:call).and_raise(Integrations::OpenRouter::EventParsing::UnparseableResponse, "boom")

      call_action("/setup_event gibberish", telegram_account)

      expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/could not turn that into an event/i)))
      expect(telegram_account.user.action_executions.failed.count).to eq(1)
    end

    context "with a synced local calendar_event for the created event" do
      let!(:local_event) do
        create(:calendar_event, user: telegram_account.user, external_event_id: created_event.id, provider: "google",
               external_calendar_id: "primary",
               title: event.title, starts_at: event.starts_at, ends_at: event.ends_at)
      end

      it "asks about a reminder when the user has no preference set (defaults to ask every time)" do
        call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)

        expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/want a reminder/i)))
      end

      it "asks about a reminder when the preference is explicitly ask_every_time" do
        create(:reminder_preference, user: telegram_account.user, event_reminder_mode: :ask_every_time)

        call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)

        expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/want a reminder/i)))
      end

      it "does not ask and does not create a reminder when disabled" do
        create(:reminder_preference, user: telegram_account.user, event_reminder_mode: :disabled_by_default)

        expect {
          call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)
        }.not_to change(Reminder, :count)
        expect(telegram_api).not_to have_received(:send_message).with(hash_including(text: a_string_matching(/want a reminder/i)))
      end

      it "automatically creates a reminder when the preference is always_apply_default" do
        create(:reminder_preference, user: telegram_account.user, event_reminder_mode: :always_apply_default, default_event_offset_minutes: 30)

        call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)

        reminder = telegram_account.user.reminders.last
        expect(reminder.remindable).to eq(local_event)
        expect(reminder.offset_minutes).to eq(30)
        expect(reminder.scheduled_at).to eq(local_event.starts_at - 30.minutes)
        expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/added a reminder 30 minutes/i)))
      end

      it "creates a reminder when the user replies to the follow-up prompt with an offset" do
        pending = { command: "/setup_event", stage: "reminder_choice", calendar_event_id: local_event.id }

        call_action("1 hour before", telegram_account, pending: pending)

        reminder = telegram_account.user.reminders.last
        expect(reminder.remindable).to eq(local_event)
        expect(reminder.offset_minutes).to eq(60)
        expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/added a reminder 1 hour/i)))
      end

      it "adds no reminder when the user declines the follow-up prompt" do
        pending = { command: "/setup_event", stage: "reminder_choice", calendar_event_id: local_event.id }

        expect {
          call_action("no", telegram_account, pending: pending)
        }.not_to change(Reminder, :count)
        expect(telegram_api).to have_received(:send_message).with(hash_including(text: a_string_matching(/no reminder added/i)))
      end

      it "allows 0 minutes (a reminder exactly at event time), not treated as a decline" do
        pending = { command: "/setup_event", stage: "reminder_choice", calendar_event_id: local_event.id }

        call_action("0 minutes before", telegram_account, pending: pending)

        expect(telegram_account.user.reminders.last.offset_minutes).to eq(0)
      end

      it "clamps an absurdly large offset in the follow-up reply instead of raising a database range error" do
        pending = { command: "/setup_event", stage: "reminder_choice", calendar_event_id: local_event.id }

        expect {
          call_action("999999999999999999999 days before", telegram_account, pending: pending)
        }.not_to raise_error

        expect(telegram_account.user.reminders.last.offset_minutes).to eq(Reminder::MAX_OFFSET_MINUTES)
      end
    end

    # A provider event id identifies a row only together with its calendar:
    # the unique index is (user, provider, external_calendar_id,
    # external_event_id), so two calendars can legitimately hold the same id.
    context "when the same provider event id also exists in another calendar" do
      let(:selected_calendar) { "work@group.calendar.google.com" }

      # "archive@" is chosen because it was OBSERVED to expose the defect, not
      # because the query promises an order — `find_by` has no ORDER BY. The
      # plan measured on this schema is
      #   SEARCH calendar_events USING INDEX
      #     index_calendar_events_on_user_provider_calendar_external_id
      #     (user_id=? AND provider=?)
      # i.e. only the two-column prefix is used and the remaining index entries
      # are scanned in external_calendar_id order, so "archive@" is reached
      # before "work@" whichever row is inserted first. A competing calendar
      # sorting *after* "work@" returned the correct row and hid the bug
      # completely, which is why the fixture value is load-bearing.
      let(:competing_calendar) { "archive@group.calendar.google.com" }
      let(:create_result) do
        Integrations::Google::CreateEvent::Result.new(provider_event: created_event, calendar_id: selected_calendar)
      end

      let!(:competing_event) do
        create(:calendar_event, user: telegram_account.user, provider: "google",
               external_calendar_id: competing_calendar, external_event_id: created_event.id,
               title: "Archived copy", starts_at: event.starts_at - 10.hours, ends_at: event.ends_at - 10.hours)
      end
      let!(:selected_event) do
        create(:calendar_event, user: telegram_account.user, provider: "google",
               external_calendar_id: selected_calendar, external_event_id: created_event.id,
               title: event.title, starts_at: event.starts_at, ends_at: event.ends_at)
      end

      before { UserSetting.create!(user_id: telegram_account.user.id, default_calendar_id: selected_calendar) }

      it "applies the default reminder to the event in the calendar CreateEvent wrote to, at that event's time" do
        create(:reminder_preference, user: telegram_account.user,
               event_reminder_mode: :always_apply_default, default_event_offset_minutes: 30)

        call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)

        reminder = telegram_account.user.reminders.last
        expect(reminder.remindable).to eq(selected_event)
        expect(reminder.remindable).not_to eq(competing_event)
        expect(reminder.scheduled_at).to eq(selected_event.starts_at - 30.minutes)
        expect(reminder.scheduled_at).not_to eq(competing_event.starts_at - 30.minutes)
      end

      it "offers the reminder for that same event when the preference asks every time" do
        create(:reminder_preference, user: telegram_account.user, event_reminder_mode: :ask_every_time)
        allow(TelegramBot::PendingAction).to receive(:set).and_call_original

        call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)

        expect(TelegramBot::PendingAction).to have_received(:set).with(
          telegram_account.telegram_user_id.to_i,
          command: described_class::COMMAND, stage: "reminder_choice",
          calendar_event_id: selected_event.id
        )
      end
    end
  end

  it "tells the user the event is in their calendar when Google succeeds but local save fails" do
    telegram_account = create(:telegram_account)
    create(:user_integration, user: telegram_account.user)
    unsaveable = Integrations::OpenRouter::EventParsing::Event.new(
      title: nil, description: nil, location: nil,
      starts_at: Time.zone.parse("2026-08-10 19:00"), ends_at: Time.zone.parse("2026-08-10 20:00"), all_day: false
    )
    google_event = Google::Apis::CalendarV3::Event.new(id: "gcal_event_x", html_link: "https://calendar.google.com/x")
    calendar = instance_double(Google::Apis::CalendarV3::CalendarService)
    allow(calendar).to receive(:insert_event).and_return(google_event)
    allow(Integrations::Google::Client).to receive(:new).and_return(instance_double(Integrations::Google::Client, calendar: calendar))
    allow(Integrations::OpenRouter::ParseEvent).to receive(:call).and_return(unsaveable)

    expect {
      call_action("/setup_event dinner with Anna tomorrow at 19:00", telegram_account)
    }.not_to raise_error

    expect(CalendarEvent.where(external_event_id: google_event.id)).to be_empty
    execution = telegram_account.user.action_executions.failed.last
    expect(execution).to be_present
    expect(execution.error_message).to include("provider_event_id=#{google_event.id}")
    expect(telegram_api).to have_received(:send_message).with(
      hash_including(text: I18n.t("telegram_bot.commands.setup_event.local_save_failed", raise: true))
    )
    expect(telegram_api).not_to have_received(:send_message).with(
      hash_including(text: I18n.t("telegram_bot.commands.setup_event.failed"))
    )
  end
end
