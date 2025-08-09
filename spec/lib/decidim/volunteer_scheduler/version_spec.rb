# frozen_string_literal: true

require "spec_helper"

module Decidim
  describe VolunteerScheduler do
    subject { described_class }

    it "has version" do
      expect(subject.version).to eq("0.30.1")
    end
  end
end
