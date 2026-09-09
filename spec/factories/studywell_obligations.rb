FactoryBot.define do
  factory :studywell_obligation, class: "Studywell::Obligation" do
    user
    course { association :studywell_course, user: user }
    kind { :assignment }
    title { "Problem set 1" }

    trait :exam do
      kind { :exam }
    end

    trait :study_task do
      kind { :study_task }
    end

    trait :done do
      status { :done }
      completed_at { Time.current }
    end
  end
end
