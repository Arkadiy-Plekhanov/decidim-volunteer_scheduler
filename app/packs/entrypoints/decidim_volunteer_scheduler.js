// Volunteer Scheduler JavaScript Entry Point
// Provides interactive functionality for the volunteer scheduler component

import "src/decidim/volunteer_scheduler/volunteer_scheduler"

// Initialize when DOM is ready
document.addEventListener("DOMContentLoaded", function() {
  // Initialize all volunteer scheduler functionality
  window.DecidimVolunteerScheduler.init();
});

// Export for global access
window.DecidimVolunteerScheduler = window.DecidimVolunteerScheduler || {};
