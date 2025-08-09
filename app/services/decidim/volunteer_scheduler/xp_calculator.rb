# frozen_string_literal: true

module Decidim
  module VolunteerScheduler
    # Service for calculating XP and level progressions
    class XpCalculator
      def initialize(component)
        @component = component
      end

      def level_for_xp(total_xp)
        thresholds = level_thresholds
        level = 1
        
        thresholds.each_with_index do |threshold, index|
          if total_xp >= threshold
            level = index + 2
          else
            break
          end
        end
        
        level
      end

      def xp_needed_for_level(target_level)
        thresholds = level_thresholds
        return 0 if target_level <= 1
        return thresholds.last if target_level > thresholds.length + 1
        
        thresholds[target_level - 2]
      end

      def next_level_xp(current_xp, current_level)
        thresholds = level_thresholds
        return nil if current_level >= thresholds.length + 1
        
        next_threshold = thresholds[current_level - 1]
        next_threshold - current_xp
      end

      def level_progress_percentage(current_xp, current_level)
        thresholds = level_thresholds
        return 100 if current_level >= thresholds.length + 1
        
        current_threshold = current_level > 1 ? thresholds[current_level - 2] : 0
        next_threshold = thresholds[current_level - 1]
        
        return 100 if next_threshold <= current_threshold
        
        progress = current_xp - current_threshold
        total_needed = next_threshold - current_threshold
        
        [(progress.to_f / total_needed * 100).round, 100].min
      end

      def level_rewards(level)
        case level
        when 2
          { tokens: 50, title: "Committed Volunteer" }
        when 3
          { tokens: 100, title: "Dedicated Volunteer", permissions: [:create_tasks] }
        when 4
          { tokens: 200, title: "Senior Volunteer", permissions: [:mentor_others] }
        when 5
          { tokens: 500, title: "Volunteer Leader", permissions: [:manage_teams] }
        else
          {}
        end
      end

      private

      def level_thresholds
        @level_thresholds ||= @component.settings.level_thresholds
                                       .split(",")
                                       .map(&:strip)
                                       .map(&:to_i)
                                       .select(&:positive?)
      end
    end
  end
end
