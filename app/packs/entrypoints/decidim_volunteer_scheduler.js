// Volunteer Scheduler JavaScript Entry Point
console.log("Decidim Volunteer Scheduler loaded");

// Import CSS styles
import "stylesheets/decidim/volunteer_scheduler/volunteer_scheduler.scss"

// Simple copy to clipboard functionality
document.addEventListener("DOMContentLoaded", function() {
  const copyButtons = document.querySelectorAll('[data-copy-target]');
  
  copyButtons.forEach(button => {
    button.addEventListener('click', function(e) {
      e.preventDefault();
      const input = this.previousElementSibling;
      if (input && input.tagName === 'INPUT') {
        input.select();
        document.execCommand('copy');
        
        const originalText = this.textContent;
        this.textContent = this.getAttribute('data-copied-text') || 'Copied!';
        
        setTimeout(() => {
          this.textContent = originalText;
        }, 2000);
      }
    });
  });
});
