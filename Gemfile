source 'http://rubygems.org'

gem 'rails', '3.1.3'
gem 'rake',  '0.8.7'

gem 'mysql2', '0.3.11'
gem 'airbrake', '3.0.9'

#gem 'federal_register', '0.5.0'
#gem 'federal_register', :path => '../federal_register'
gem 'federal_register', :git => "git://github.com/criticaljuncture/federal_register.git", :ref => "f1e21a016f258862133eb8f8342bbdde1c10492e"

gem 'devise', '1.5.0'
gem 'omniauth', '1.0.1'
gem 'omniauth-facebook', '1.0.0'
gem 'omniauth-twitter', '0.0.7'

gem 'formtastic', '2.0.2'
gem 'draper',     '0.9.5'

gem 'jquery-rails'
gem 'sass-rails',    "~> 3.1.0"
gem 'compass-rails', "1.0.0"
gem 'oily_png',   "1.0.2"  # C binding for the pure ruby chunky_png used by compass

gem 'userstamp', '2.0.1'

gem "capistrano", '2.5.19', :require => false
gem "thunder_punch", '0.0.11', :require => false

# Gems used only for assets and not required
# in production environments by default.
group :assets do 
  gem 'sass-rails',    "~> 3.1.0"
  gem 'compass-rails', "1.0.0"
  gem 'oily_png',   "1.0.2"  # C binding for the pure ruby chunky_png used by compass

  gem 'uglifier'
end

# group :staging do
#   gem 'therubyracer'
# end

group :development do
  gem 'mongrel', '1.1.5'
end

group :development, :test do 
  gem 'rspec-rails',                    '>= 2.5'
  gem 'watchr',                         '0.7'
  gem 'spork',                          '~> 0.8.5'
  gem 'factory_girl_rails',             '~> 1.1.0',      :require => false
  gem 'shoulda-matchers',               '1.0.0.beta3'
end
