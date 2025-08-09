# frozen_string_literal: true

require "decidim/components/namer"

Decidim.register_component(:volunteer_scheduler) do |component|
  component.engine = Decidim::VolunteerScheduler::Engine
  component.admin_engine = Decidim::VolunteerScheduler::AdminEngine
  component.icon = "decidim/volunteer_scheduler/icon.svg"
  component.permissions_class_name = "Decidim::VolunteerScheduler::Permissions"

  component.on(:before_destroy) do |instance|
    Decidim::VolunteerScheduler::TaskTemplate.where(component: instance).find_each(&:destroy!)
  end

  component.register_resource(:task_template) do |resource|
    resource.model_class_name = "Decidim::VolunteerScheduler::TaskTemplate"
    resource.template = "decidim/volunteer_scheduler/task_templates/linked_task_templates"
  end

  component.register_resource(:task_assignment) do |resource|
    resource.model_class_name = "Decidim::VolunteerScheduler::TaskAssignment"
  end

  component.settings(:global) do |settings|
    settings.attribute :xp_per_task, type: :integer, default: 20
    settings.attribute :max_daily_tasks, type: :integer, default: 5
    settings.attribute :referral_commission_l1, type: :float, default: 0.10
    settings.attribute :referral_commission_l2, type: :float, default: 0.08
    settings.attribute :referral_commission_l3, type: :float, default: 0.06
    settings.attribute :referral_commission_l4, type: :float, default: 0.04
    settings.attribute :referral_commission_l5, type: :float, default: 0.02
    settings.attribute :level_thresholds, type: :text, default: "100,300,600,1000,2000"
    settings.attribute :task_deadline_days, type: :integer, default: 7
  end

  component.settings(:step) do |settings|
    settings.attribute :task_assignment_enabled, type: :boolean, default: true
    settings.attribute :task_submission_enabled, type: :boolean, default: true
  end

  component.exports :task_assignments do |exports|
    exports.collection do |component_instance|
      Decidim::VolunteerScheduler::TaskAssignment
        .joins(:task_template)
        .where(decidim_volunteer_scheduler_task_templates: { component: component_instance })
    end

    exports.include_in_open_data = true
    exports.serializer Decidim::VolunteerScheduler::TaskAssignmentSerializer
  end

  component.newsletter_participant_entities do |component_instance|
    Decidim::User.joins(:volunteer_profile)
                 .where(decidim_volunteer_scheduler_volunteer_profiles: { component: component_instance })
  end

  component.register_stat :total_volunteers do |component_instance, start_at, end_at|
    Decidim::VolunteerScheduler::VolunteerProfile
      .where(component: component_instance)
      .where(created_at: start_at..end_at)
      .count
  end

  component.register_stat :completed_tasks do |component_instance, start_at, end_at|
    Decidim::VolunteerScheduler::TaskAssignment
      .joins(:task_template)
      .where(decidim_volunteer_scheduler_task_templates: { component: component_instance })
      .where(status: :approved)
      .where(created_at: start_at..end_at)
      .count
  end

  component.seeds do |participatory_space|
    admin_user = Decidim::User.find_by(
      organization: participatory_space.organization,
      admin: true
    )

    step_settings = if participatory_space.allows_steps?
                      { participatory_space.active_step.id => { task_assignment_enabled: true } }
                    else
                      {}
                    end

    params = {
      name: Decidim::Components::Namer.new(participatory_space.organization.available_locales, :volunteer_scheduler).i18n_name,
      manifest_name: :volunteer_scheduler,
      published_at: Time.current,
      participatory_space: participatory_space,
      settings: {
        xp_per_task: 50,
        max_daily_tasks: 3,
        level_thresholds: "100,500,1500,3000,6000"
      },
      step_settings: step_settings
    }

    component = Decidim.traceability.perform_action!(
      "publish",
      Decidim::Component,
      admin_user,
      visibility: "all"
    ) do
      Decidim::Component.create!(params)
    end

    # Create sample organization-level task templates
    3.times do |i|
      params = {
        organization: participatory_space.organization,
        component: component,
        title: Decidim::Faker::Localized.sentence(word_count: 2),
        description: Decidim::Faker::Localized.wrapped("<p>", "</p>") { Decidim::Faker::Localized.paragraph(sentence_count: 3) },
        xp_reward: [20, 50, 100].sample,
        level_required: i + 1,
        category: ["outreach", "technical", "administrative"].sample,
        frequency: ["daily", "weekly", "monthly"].sample,
        status: :published
      }

      task_template = Decidim.traceability.create!(
        Decidim::VolunteerScheduler::TaskTemplate,
        admin_user,
        params,
        visibility: "all"
      )
    end
  end
end
