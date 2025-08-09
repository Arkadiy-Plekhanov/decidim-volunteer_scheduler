// Volunteer Scheduler Core JavaScript Module
// Handles interactive features for volunteer management

((exports) => {
  const VolunteerScheduler = {
    
    // Initialize all functionality
    init() {
      this.initCopyToClipboard();
      this.initBulkActions();
      this.initTaskFilters();
      this.initProgressAnimations();
      this.initFormValidations();
      this.initNotifications();
      this.initAutoRefresh();
    },

    // Copy referral links to clipboard
    initCopyToClipboard() {
      const copyButtons = document.querySelectorAll('[data-copy-target]');
      
      copyButtons.forEach(button => {
        button.addEventListener('click', (e) => {
          e.preventDefault();
          const targetSelector = button.dataset.copyTarget;
          const targetElement = document.querySelector(targetSelector);
          
          if (targetElement) {
            this.copyToClipboard(targetElement.value || targetElement.textContent);
            this.showCopyFeedback(button);
          }
        });
      });
    },

    // Copy text to clipboard with fallback
    copyToClipboard(text) {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text);
      } else {
        // Fallback for older browsers
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.opacity = '0';
        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();
        try {
          document.execCommand('copy');
        } catch (err) {
          console.error('Failed to copy text:', err);
        }
        document.body.removeChild(textArea);
      }
    },

    // Show visual feedback when copying
    showCopyFeedback(button) {
      const originalText = button.textContent;
      button.textContent = button.dataset.copiedText || 'Copied!';
      button.classList.add('success');
      
      setTimeout(() => {
        button.textContent = originalText;
        button.classList.remove('success');
      }, 2000);
    },

    // Handle bulk actions for assignments
    initBulkActions() {
      const selectAllCheckboxes = document.querySelectorAll('[data-select-all]');
      const bulkActionForms = document.querySelectorAll('[data-bulk-actions]');
      
      selectAllCheckboxes.forEach(selectAll => {
        const targetSelector = selectAll.dataset.selectAll;
        const checkboxes = document.querySelectorAll(targetSelector);
        
        selectAll.addEventListener('change', () => {
          checkboxes.forEach(checkbox => {
            checkbox.checked = selectAll.checked;
          });
          this.updateBulkActionButtons();
        });
        
        checkboxes.forEach(checkbox => {
          checkbox.addEventListener('change', () => {
            const allChecked = Array.from(checkboxes).every(cb => cb.checked);
            const noneChecked = Array.from(checkboxes).every(cb => !cb.checked);
            
            selectAll.checked = allChecked;
            selectAll.indeterminate = !allChecked && !noneChecked;
            this.updateBulkActionButtons();
          });
        });
      });
      
      bulkActionForms.forEach(form => {
        form.addEventListener('submit', (e) => {
          const checkedBoxes = form.querySelectorAll('input[type="checkbox"]:checked');
          if (checkedBoxes.length === 0) {
            e.preventDefault();
            this.showNotification('Please select at least one item.', 'warning');
          }
        });
      });
    },

    // Update bulk action button states
    updateBulkActionButtons() {
      const selectedCount = document.querySelectorAll('input[name="assignment_ids[]"]:checked').length;
      const bulkButtons = document.querySelectorAll('[data-bulk-button]');
      
      bulkButtons.forEach(button => {
        button.disabled = selectedCount === 0;
        if (button.dataset.countTarget) {
          const countElement = document.querySelector(button.dataset.countTarget);
          if (countElement) {
            countElement.textContent = selectedCount;
          }
        }
      });
    },

    // Filter tasks and assignments
    initTaskFilters() {
      const filterButtons = document.querySelectorAll('[data-filter]');
      const filterableItems = document.querySelectorAll('[data-filterable]');
      
      filterButtons.forEach(button => {
        button.addEventListener('click', (e) => {
          e.preventDefault();
          const filterValue = button.dataset.filter;
          
          // Update active filter button
          filterButtons.forEach(btn => btn.classList.remove('active', 'secondary'));
          button.classList.add('active', 'secondary');
          
          // Filter items
          filterableItems.forEach(item => {
            const itemFilters = item.dataset.filterable.split(',');
            const shouldShow = filterValue === 'all' || itemFilters.includes(filterValue);
            
            item.style.display = shouldShow ? '' : 'none';
          });
          
          this.updateFilterCount(filterValue);
        });
      });
    },

    // Update filter result count
    updateFilterCount(activeFilter) {
      const countElement = document.querySelector('[data-filter-count]');
      if (countElement) {
        const visibleItems = document.querySelectorAll('[data-filterable]:not([style*="display: none"])');
        countElement.textContent = `${visibleItems.length} items`;
      }
    },

    // Animate progress bars
    initProgressAnimations() {
      const progressBars = document.querySelectorAll('.progress-meter');
      
      // Animate progress bars on scroll
      const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const progressMeter = entry.target;
            const targetWidth = progressMeter.dataset.progress || progressMeter.style.width;
            
            progressMeter.style.width = '0%';
            progressMeter.style.transition = 'width 1s ease-out';
            
            setTimeout(() => {
              progressMeter.style.width = targetWidth;
            }, 100);
            
            observer.unobserve(progressMeter);
          }
        });
      });
      
      progressBars.forEach(bar => observer.observe(bar));
    },

    // Form validation enhancements
    initFormValidations() {
      const forms = document.querySelectorAll('form[data-validate]');
      
      forms.forEach(form => {
        form.addEventListener('submit', (e) => {
          if (!this.validateForm(form)) {
            e.preventDefault();
          }
        });
        
        // Real-time validation
        const inputs = form.querySelectorAll('input, textarea, select');
        inputs.forEach(input => {
          input.addEventListener('blur', () => {
            this.validateField(input);
          });
        });
      });
    },

    // Validate individual form field
    validateField(field) {
      const rules = field.dataset.validate?.split(',') || [];
      let isValid = true;
      let errorMessage = '';
      
      rules.forEach(rule => {
        const [ruleName, ruleValue] = rule.split(':');
        
        switch(ruleName) {
          case 'required':
            if (!field.value.trim()) {
              isValid = false;
              errorMessage = 'This field is required.';
            }
            break;
          case 'min':
            if (field.value.length < parseInt(ruleValue)) {
              isValid = false;
              errorMessage = `Minimum ${ruleValue} characters required.`;
            }
            break;
          case 'max':
            if (field.value.length > parseInt(ruleValue)) {
              isValid = false;
              errorMessage = `Maximum ${ruleValue} characters allowed.`;
            }
            break;
          case 'number':
            if (field.value && isNaN(field.value)) {
              isValid = false;
              errorMessage = 'Please enter a valid number.';
            }
            break;
        }
      });
      
      this.showFieldValidation(field, isValid, errorMessage);
      return isValid;
    },

    // Show field validation state
    showFieldValidation(field, isValid, message) {
      // Remove existing validation
      const existingError = field.parentNode.querySelector('.field-error');
      if (existingError) {
        existingError.remove();
      }
      
      field.classList.remove('is-invalid-input', 'is-valid-input');
      
      if (!isValid && message) {
        field.classList.add('is-invalid-input');
        const errorElement = document.createElement('span');
        errorElement.className = 'form-error is-visible field-error';
        errorElement.textContent = message;
        field.parentNode.appendChild(errorElement);
      } else if (isValid && field.value) {
        field.classList.add('is-valid-input');
      }
    },

    // Validate entire form
    validateForm(form) {
      const fields = form.querySelectorAll('[data-validate]');
      let isFormValid = true;
      
      fields.forEach(field => {
        if (!this.validateField(field)) {
          isFormValid = false;
        }
      });
      
      return isFormValid;
    },

    // Show notifications
    initNotifications() {
      // Auto-hide flash messages
      const flashMessages = document.querySelectorAll('.flash');
      flashMessages.forEach(message => {
        setTimeout(() => {
          this.hideNotification(message);
        }, 5000);
        
        // Add close button
        const closeButton = document.createElement('button');
        closeButton.innerHTML = '×';
        closeButton.className = 'close-button';
        closeButton.addEventListener('click', () => {
          this.hideNotification(message);
        });
        message.appendChild(closeButton);
      });
    },

    // Show notification message
    showNotification(message, type = 'info') {
      const notification = document.createElement('div');
      notification.className = `callout ${type} notification-toast`;
      notification.innerHTML = `
        ${message}
        <button class="close-button" aria-label="Dismiss alert">&times;</button>
      `;
      
      document.body.appendChild(notification);
      
      // Auto-hide after 5 seconds
      setTimeout(() => {
        this.hideNotification(notification);
      }, 5000);
      
      // Add close button functionality
      const closeButton = notification.querySelector('.close-button');
      closeButton.addEventListener('click', () => {
        this.hideNotification(notification);
      });
    },

    // Hide notification with animation
    hideNotification(notification) {
      notification.style.opacity = '0';
      notification.style.transform = 'translateX(100%)';
      setTimeout(() => {
        if (notification.parentNode) {
          notification.parentNode.removeChild(notification);
        }
      }, 300);
    },

    // Auto-refresh dashboard data
    initAutoRefresh() {
      const autoRefreshElements = document.querySelectorAll('[data-auto-refresh]');
      
      autoRefreshElements.forEach(element => {
        const interval = parseInt(element.dataset.autoRefresh) || 30000; // 30 seconds default
        
        setInterval(() => {
          this.refreshElement(element);
        }, interval);
      });
    },

    // Refresh element content via AJAX
    refreshElement(element) {
      const url = element.dataset.refreshUrl || window.location.href;
      
      fetch(url, {
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'text/html'
        }
      })
      .then(response => response.text())
      .then(html => {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const newElement = doc.querySelector(`[data-auto-refresh="${element.dataset.autoRefresh}"]`);
        
        if (newElement) {
          element.innerHTML = newElement.innerHTML;
          // Re-initialize any JavaScript functionality
          this.initProgressAnimations();
        }
      })
      .catch(error => {
        console.error('Auto-refresh failed:', error);
      });
    },

    // Utility: Debounce function calls
    debounce(func, wait) {
      let timeout;
      return function executedFunction(...args) {
        const later = () => {
          clearTimeout(timeout);
          func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
      };
    },

    // Utility: Format numbers
    formatNumber(num) {
      return new Intl.NumberFormat().format(num);
    },

    // Utility: Format dates
    formatDate(date) {
      return new Intl.DateTimeFormat().format(new Date(date));
    }
  };

  exports.VolunteerScheduler = VolunteerScheduler;
})(window.DecidimVolunteerScheduler = window.DecidimVolunteerScheduler || {});
