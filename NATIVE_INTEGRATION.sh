#!/bin/bash

# Native Decidim Module Integration Script
# This script follows official Decidim integration specifications

echo "🚀 Starting Native Decidim Integration for decidim-volunteer_scheduler"

# Change to development app directory
cd /home/scicent/projects/decidim/development_app

echo "📍 Working from: $(pwd)"

# Verify we're in the right directory
if [ ! -f "Gemfile" ] || [ ! -f "config/application.rb" ]; then
    echo "❌ Error: Not in a valid Rails application directory"
    echo "Expected to find Gemfile and config/application.rb"
    exit 1
fi

echo "✅ Confirmed we're in a Rails application"

# Step 1: Verify gem is in Gemfile
echo "📋 Step 1: Verifying gem in Gemfile..."
if grep -q "decidim-volunteer_scheduler" Gemfile; then
    echo "✅ Gem found in Gemfile"
else
    echo "❌ Gem not found in Gemfile"
    exit 1
fi

# Step 2: Install dependencies
echo "📦 Step 2: Installing dependencies with bundle install..."
bundle install
if [ $? -eq 0 ]; then
    echo "✅ Bundle install completed successfully"
else
    echo "❌ Bundle install failed"
    exit 1
fi

# Step 3: Install migrations using native Decidim method
echo "🗄️ Step 3: Installing migrations using native Decidim method..."

# Try the Decidim-specific rake task first
if bundle exec rails decidim_volunteer_scheduler:install:migrations 2>/dev/null; then
    echo "✅ Migrations installed using Decidim-specific task"
else
    echo "⚠️ Decidim-specific task failed, trying Rails standard method..."
    # Fallback to Rails standard method
    if bundle exec rails railties:install:migrations FROM=decidim_volunteer_scheduler; then
        echo "✅ Migrations installed using Rails standard method"
    else
        echo "❌ Migration installation failed"
        exit 1
    fi
fi

# Step 4: Install webpacker assets (if applicable)
echo "📦 Step 4: Installing webpacker assets..."
if bundle exec rails decidim_volunteer_scheduler:webpacker:install 2>/dev/null; then
    echo "✅ Webpacker assets installed"
else
    echo "ℹ️ Webpacker install not available or not needed"
fi

# Step 5: Run migrations
echo "🔄 Step 5: Running database migrations..."
if bundle exec rails db:migrate; then
    echo "✅ Database migrations completed"
else
    echo "❌ Database migration failed"
    exit 1
fi

# Step 6: Verify installation
echo "🧪 Step 6: Verifying installation..."

# Check that tables were created
echo "📋 Checking database tables..."
TABLES=$(bundle exec rails runner "puts ActiveRecord::Base.connection.tables.select { |t| t.include?('volunteer_scheduler') }.join(', ')")

if [ -n "$TABLES" ]; then
    echo "✅ Volunteer scheduler tables created: $TABLES"
else
    echo "❌ No volunteer scheduler tables found"
    exit 1
fi

# Check component registration
echo "📦 Checking component registration..."
COMPONENT_CHECK=$(bundle exec rails runner "
begin
  manifest = Decidim.component_manifests.find { |m| m.name == :volunteer_scheduler }
  if manifest
    puts 'Component registered successfully'
    exit 0
  else
    puts 'Component not found'
    exit 1
  end
rescue => e
  puts \"Error: #{e.message}\"
  exit 1
end
")

if [ $? -eq 0 ]; then
    echo "✅ Component registration verified"
else
    echo "❌ Component registration failed"
    echo "$COMPONENT_CHECK"
    exit 1
fi

# Step 7: Success summary
echo ""
echo "🎉 NATIVE INTEGRATION COMPLETE!"
echo ""
echo "📋 Installation Summary:"
echo "  ✅ Gem added to Gemfile"
echo "  ✅ Dependencies installed with bundle"
echo "  ✅ Migrations installed using native methods"
echo "  ✅ Database migrations completed"
echo "  ✅ Component registered in Decidim"
echo "  ✅ Database tables created"
echo ""
echo "🚀 Next Steps:"
echo "1. Start the development server:"
echo "   rails server"
echo ""
echo "2. Visit http://localhost:3000"
echo ""
echo "3. Login as admin and:"
echo "   - Create or edit a Participatory Process"
echo "   - Add 'Volunteer Scheduler' component"
echo "   - Configure component settings"
echo ""
echo "4. Test the volunteer workflow:"
echo "   - Create task templates (admin)"
echo "   - Accept tasks (volunteer)"
echo "   - Complete and submit tasks"
echo "   - Review submissions (admin)"
echo ""
echo "📖 For detailed usage, see the module documentation."
echo "🎯 The module is now fully integrated using native Decidim methods!"