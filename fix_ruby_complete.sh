#!/bin/bash
echo "🔧 Fixing Ruby completely..."

# 1. Update ruby-build
sudo apt remove ruby-build
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build

# 2. Check available versions
echo "Available Ruby versions:"
rbenv install --list | grep "^3\.3"

# 3. Install Ruby 3.3.x (use available version)
RUBY_VERSION=$(rbenv install --list | grep "^3\.3\." | tail -1 | xargs)
echo "Installing $RUBY_VERSION..."
rbenv install $RUBY_VERSION
rbenv global $RUBY_VERSION

# 4. Fix gem permissions
echo 'export GEM_HOME="$HOME/.gem"' >> ~/.bashrc
echo 'export PATH="$HOME/.gem/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 5. Install bundler
gem install bundler

# 6. Update Gemfile if needed
cd ~/Projects/active_plus_demo
sed -i "s/3\.3\.2/$RUBY_VERSION/" Gemfile

echo "✅ Ruby $RUBY_VERSION installed!"
ruby -v
