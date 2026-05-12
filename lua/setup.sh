#!/bin/bash
# setup.sh - Install Lua and dependencies

# Verify administrator privileges if needed
check_sudo() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Some operations may require administrator privileges"
  fi
}

# Install Lua and LuaRocks based on OS
install_lua() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Installing Lua environment on macOS..."
    if command -v brew >/dev/null; then
      echo "Using Homebrew to install Lua and LuaRocks..."
      brew install lua luarocks
    else
      echo "Homebrew not found. Installing from source..."
      # Install dependencies (Xcode command line tools should provide what we need)
      if ! command -v xcode-select -p >/dev/null; then
        echo "Installing Xcode Command Line Tools..."
        xcode-select --install
      fi
      
      # Download and install latest Lua from source
      cd /tmp || exit 1
      curl -L -R -O "https://www.lua.org/ftp/lua-5.4.7.tar.gz"
      tar zxf "lua-5.4.7.tar.gz"
      cd "lua-5.4.7" || exit 1
      make macosx test
      sudo make install
      
      # Download and install latest LuaRocks from source
      cd /tmp || exit 1
      curl -L -R -O "https://luarocks.org/releases/luarocks-3.11.1.tar.gz"
      tar zxpf "luarocks-3.11.1.tar.gz"
      cd "luarocks-3.11.1" || exit 1
      ./configure && make && sudo make install
    fi
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Installing latest Lua environment on Linux..."
    
    # Check for package manager and install build dependencies
    if command -v apt-get >/dev/null; then
      echo "Debian-based system detected"
      sudo apt-get update
      sudo apt-get install -y build-essential libreadline-dev
    elif command -v dnf >/dev/null; then
      echo "Fedora/RHEL-based system detected"
      sudo dnf install -y make gcc readline-devel
    elif command -v pacman >/dev/null; then
      echo "Arch-based system detected"
      sudo pacman -Sy base-devel readline
    else
      echo "Unknown Linux distribution. Ensure you have build tools (gcc, make) and readline development libraries installed."
    fi
    
    # Download and install latest Lua from source
    cd /tmp || exit 1
    curl -L -R -O "https://www.lua.org/ftp/lua-5.4.7.tar.gz"  # Current latest stable
    tar zxf "lua-5.4.7.tar.gz"
    cd "lua-5.4.7" || exit 1
    make all test
    sudo make install
    
    # Download and install latest LuaRocks from source
    cd /tmp || exit 1
    curl -L -R -O "https://luarocks.org/releases/luarocks-3.11.1.tar.gz"
    tar zxpf "luarocks-3.11.1.tar.gz"
    cd "luarocks-3.11.1" || exit 1
    ./configure --with-lua-include=/usr/local/include && make && sudo make install
  else
    echo "Unsupported OS: $OSTYPE"
    exit 1
  fi
}

# Install required Lua packages
install_dependencies() {
  echo "Installing Lua dependencies..."
  luarocks install busted
  luarocks install luassert
  luarocks install dkjson
  luarocks install luafilesystem
}

# Main execution
check_sudo

# Install Lua if not found
if ! command -v lua >/dev/null; then
  echo "Lua not found, installing both Lua and LuaRocks..."
  install_lua
else
  echo "Lua found: $(lua -v)"
  
  # Only install LuaRocks if not found
  if ! command -v luarocks >/dev/null; then
    echo "LuaRocks not found, installing only LuaRocks..."
    
    # Download and install only LuaRocks
    cd /tmp || exit 1
    curl -L -R -O "https://luarocks.org/releases/luarocks-3.11.1.tar.gz"
    tar zxpf "luarocks-3.11.1.tar.gz"
    cd "luarocks-3.11.1" || exit 1
    ./configure && make && sudo make install
  else
    echo "LuaRocks found: $(luarocks --version)"
  fi
fi

install_dependencies
echo "Setup complete! Run 'make test' to run the tests."
