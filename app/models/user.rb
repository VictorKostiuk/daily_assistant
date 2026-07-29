class User < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  has_one :user_setting, dependent: :destroy
  has_one :reminder_preference, dependent: :destroy
  has_one :telegram_account, dependent: :destroy
  has_one :daily_digest, dependent: :destroy

  has_many :connection_tokens, dependent: :destroy
  has_many :user_integrations, dependent: :destroy
  has_many :integration_providers, through: :user_integrations

  has_many :plan_subscriptions, dependent: :destroy
  has_many :plans, through: :plan_subscriptions

  has_many :calendar_events, dependent: :destroy
  has_many :reminders, dependent: :destroy
  has_many :scheduled_actions, dependent: :destroy
  has_many :shortcuts, dependent: :destroy
  has_many :action_executions, dependent: :destroy
  has_many :usage_counters, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy

  has_many :support_conversations, dependent: :destroy
  has_many :sent_support_messages,
           class_name: "SupportMessage",
           foreign_key: :sender_id

  has_many :audit_logs,
           foreign_key: :actor_id,
           dependent: :nullify

  validates :first_name, presence: true, length: { minimum: 2 }
  validates :last_name, presence: true, length: { minimum: 2 }
  enum :role, {
    member: 0,
    moderator: 1,
    admin: 2
  }

  enum :status, {
    active: 0,
    suspended: 1,
    blocked: 2,
    pending: 3
  }

  def google_integration
    user_integrations.for_provider(IntegrationProvider::GOOGLE).first
  end
end
