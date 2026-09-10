FactoryBot.define do
  factory :studywell_course, class: "Studywell::Course" do
    user
    name { "Algorithms" }
    code { "CS101" }
    term_label { "Fall 2026" }
    colour { "#336699" }

    trait :archived do
      archived_at { Time.current }
    end
  end
end
