module Admin
  module UsersHelper
    def user_full_name(user)
      [ user.first_name, user.last_name ].compact_blank.join(" ").presence || user.email
    end
  end
end
