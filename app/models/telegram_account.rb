class TelegramAccount < ApplicationRecord
  belongs_to :user

  validates :telegram_user_id, presence: true, uniqueness: true

  def display_name
    [ first_name, last_name ].compact_blank.join(" ").presence || username
  end
end
