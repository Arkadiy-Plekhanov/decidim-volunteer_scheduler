# frozen_string_literal: true

require "decidim/components/namer"
require "decidim/core/test/factories"

FactoryBot.define do
  factory :volunteer_scheduler_component, parent: :component do
    name { Decidim::Components::Namer.new(participatory_space.organization.available_locales, :volunteer_scheduler).i18n_name }
    manifest_name :volunteer_scheduler
    participatory_space { create(:participatory_process, :with_steps) }
  end

  # Add engine factories here
end
