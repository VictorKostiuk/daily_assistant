class AuditLog < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :target_user, class_name: "User", optional: true
  belongs_to :auditable, polymorphic: true, optional: true
end
