class SupportConversation < ApplicationRecord
  belongs_to :user

  belongs_to :assigned_moderator,
             class_name: "User",
             optional: true

  has_many :support_messages, dependent: :destroy

  enum :status, {
    open: 0,
    waiting_for_support: 1,
    waiting_for_member: 2,
    resolved: 3,
    closed: 4
  }
end
