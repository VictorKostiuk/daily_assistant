class Announcement < ApplicationRecord
  enum :audience, {
    everyone: 0,
    members: 1,
    moderators: 2,
    admins: 3,
    selected_users: 4
  }
end
