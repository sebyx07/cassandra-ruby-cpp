# Installation Guide

This guide covers the installation of Cassandra-CPP on various platforms. The gem requires compilation of native extensions, so you'll need to ensure your system has the necessary dependencies.

## Table of Contents

- [System Requirements](#system-requirements)
- [Quick Install](#quick-install)
- [Platform-Specific Instructions](#platform-specific-instructions)
  - [macOS](#macos)
  - [Ubuntu/Debian](#ubuntudebian)
  - [CentOS/RHEL/Fedora](#centosrhelfedora)
  - [Windows](#windows)
- [Docker Installation](#docker-installation)
- [Troubleshooting](#troubleshooting)
- [Verifying Installation](#verifying-installation)

## System Requirements

Before installing Cassandra-CPP, ensure your system meets these requirements:

- **Ruby**: 2.7.0 or higher (3.0+ recommended)
- **C++ Compiler**: GCC 4.8+, Clang 3.4+, or MSVC 2015+
- **CMake**: 3.10 or higher
- **DataStax C++ Driver**: 2.15.0 or higher
- **Operating System**: Linux, macOS, or Windows
- **Memory**: At least 1GB RAM for compilation
- **Cassandra**: 3.0 or higher (for runtime)

## Quick Install

For most users on supported platforms, installation is straightforward:

```bash
# Install system dependencies (example for Ubuntu)
sudo apt-get update
sudo apt-get install -y build-essential cmake libuv1-dev libssl-dev

# Install the DataStax C++ driver
wget https://github.com/datastax/cpp-driver/archive/2.16.2.tar.gz
tar xzf 2.16.2.tar.gz
cd cpp-driver-2.16.2
mkdir build && cd build
cmake ..
make
sudo make install
sudo ldconfig

# Install the gem
gem install cassandra-cpp
```

## Platform-Specific Instructions

### macOS

Using Homebrew (recommended):

```bash
# Install dependencies
brew update
brew install cmake libuv openssl

# Install DataStax C++ driver
brew tap datastax/cpp-driver
brew install cassandra-cpp-driver

# Set environment variables for OpenSSL
export OPENSSL_ROOT_DIR=$(brew --prefix openssl)
export PKG_CONFIG_PATH="${OPENSSL_ROOT_DIR}/lib/pkgconfig"

# Install the gem
gem install cassandra-cpp
```

Using MacPorts:

```bash
# Install dependencies
sudo port install cmake libuv openssl

# Build DataStax driver from source (follow Linux instructions)
# Then install the gem
gem install cassandra-cpp
```

### Ubuntu/Debian

```bash
# Update package list
sudo apt-get update

# Install build dependencies
sudo apt-get install -y \
    build-essential \
    cmake \
    git \
    libuv1-dev \
    libssl-dev \
    zlib1g-dev

# Install DataStax C++ driver from package (if available)
# For Ubuntu 20.04+
wget https://downloads.datastax.com/cpp-driver/ubuntu/20.04/cassandra-cpp-driver_2.16.2-1_amd64.deb
wget https://downloads.datastax.com/cpp-driver/ubuntu/20.04/cassandra-cpp-driver-dev_2.16.2-1_amd64.deb
sudo dpkg -i cassandra-cpp-driver_2.16.2-1_amd64.deb
sudo dpkg -i cassandra-cpp-driver-dev_2.16.2-1_amd64.deb

# Or build from source
git clone https://github.com/datastax/cpp-driver.git
cd cpp-driver
mkdir build && cd build
cmake -DCASS_BUILD_STATIC=ON -DCASS_BUILD_SHARED=ON ..
make -j$(nproc)
sudo make install
sudo ldconfig

# Install Ruby development headers if needed
sudo apt-get install -y ruby-dev

# Install the gem
gem install cassandra-cpp
```

### CentOS/RHEL/Fedora

```bash
# Install development tools
sudo yum groupinstall -y "Development Tools"
sudo yum install -y cmake git

# Install dependencies
sudo yum install -y \
    libuv-devel \
    openssl-devel \
    zlib-devel \
    ruby-devel

# For CentOS 8+ / RHEL 8+ / Fedora
sudo dnf install -y epel-release
sudo dnf install -y libuv-devel

# Build DataStax C++ driver
git clone https://github.com/datastax/cpp-driver.git
cd cpp-driver
mkdir build && cd build
cmake -DCASS_BUILD_STATIC=ON -DCASS_BUILD_SHARED=ON ..
make -j$(nproc)
sudo make install
sudo ldconfig

# Install the gem
gem install cassandra-cpp
```

### Windows

Prerequisites:
- Visual Studio 2015 or later
- CMake for Windows
- Git for Windows

```powershell
# Using PowerShell as Administrator

# Install Chocolatey if not already installed
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Install dependencies
choco install cmake git visualstudio2019buildtools

# Clone and build DataStax driver
git clone https://github.com/datastax/cpp-driver.git
cd cpp-driver
mkdir build
cd build
cmake -G "Visual Studio 16 2019" -A x64 ..
cmake --build . --config Release
cmake --install . --config Release

# Install the gem
gem install cassandra-cpp
```

## Docker Installation

For containerized environments, use our pre-built Docker image:

```dockerfile
FROM ruby:3.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libuv1-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install DataStax C++ driver
RUN cd /tmp && \
    wget https://github.com/datastax/cpp-driver/archive/2.16.2.tar.gz && \
    tar xzf 2.16.2.tar.gz && \
    cd cpp-driver-2.16.2 && \
    mkdir build && cd build && \
    cmake .. && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd / && rm -rf /tmp/cpp-driver-2.16.2*

# Install cassandra-cpp gem
RUN gem install cassandra-cpp

# Your application
WORKDIR /app
COPY . .
```

Or use the pre-built image:

```bash
docker pull cassandracpp/ruby:latest
```

## Installation from Source

If you need to install from source or contribute to development:

```bash
# Clone the repository
git clone https://github.com/your-org/cassandra-cpp.git
cd cassandra-cpp

# Install bundler if needed
gem install bundler

# Install dependencies
bundle install

# Build the native extension
bundle exec rake compile

# Run tests to verify
bundle exec rake test

# Build and install the gem locally
gem build cassandra-cpp.gemspec
gem install cassandra-cpp-*.gem
```

## Bundler Configuration

Add to your `Gemfile`:

```ruby
gem 'cassandra-cpp', '~> 2.0'

# For development from git
gem 'cassandra-cpp', git: 'https://github.com/your-org/cassandra-cpp.git'

# For a specific branch
gem 'cassandra-cpp', git: 'https://github.com/your-org/cassandra-cpp.git', branch: 'develop'
```

## Troubleshooting

### Common Installation Issues

#### 1. Cannot find DataStax C++ driver

```
ERROR: Failed to build gem native extension.
Could not find cassandra.h
```

**Solution**: Ensure the DataStax driver is installed and headers are in the include path:

```bash
# Linux/macOS
export CPATH="/usr/local/include:$CPATH"
export LIBRARY_PATH="/usr/local/lib:$LIBRARY_PATH"
export LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"

# Then retry installation
gem install cassandra-cpp
```

#### 2. OpenSSL issues on macOS

```
ld: library not found for -lssl
```

**Solution**: Link OpenSSL properly:

```bash
export LDFLAGS="-L$(brew --prefix openssl)/lib"
export CPPFLAGS="-I$(brew --prefix openssl)/include"
export PKG_CONFIG_PATH="$(brew --prefix openssl)/lib/pkgconfig"

gem install cassandra-cpp
```

#### 3. Permission denied during installation

```
ERROR: While executing gem ... (Errno::EACCES)
Permission denied @ rb_sysopen
```

**Solution**: Use RVM or rbenv instead of system Ruby, or install to user directory:

```bash
gem install cassandra-cpp --user-install
```

#### 4. Compilation errors with GCC

```
error: 'std::auto_ptr' is deprecated
```

**Solution**: Use a newer compiler or set C++ standard:

```bash
export CXXFLAGS="-std=c++11"
gem install cassandra-cpp
```

### Platform-Specific Troubleshooting

#### Alpine Linux

Alpine uses musl instead of glibc, requiring additional steps:

```dockerfile
FROM ruby:3.0-alpine

RUN apk add --no-cache \
    build-base \
    cmake \
    libuv-dev \
    openssl-dev \
    linux-headers \
    git

# Build DataStax driver with musl compatibility
RUN cd /tmp && \
    git clone https://github.com/datastax/cpp-driver.git && \
    cd cpp-driver && \
    mkdir build && cd build && \
    cmake -DCASS_BUILD_STATIC=ON .. && \
    make && make install
```

#### FreeBSD

```bash
# Install from ports
cd /usr/ports/databases/cassandra-cpp-driver
make install clean

# Install the gem
gem install cassandra-cpp
```

## Verifying Installation

After installation, verify everything is working:

```ruby
# Create a test file: test_install.rb
require 'cassandra_cpp'

puts "Cassandra-CPP version: #{CassandraCpp::VERSION}"
puts "Driver version: #{CassandraCpp.driver_version}"

# Test basic functionality
begin
  cluster = CassandraCpp::Cluster.build do |c|
    c.hosts = ['127.0.0.1']
  end
  puts "✓ Successfully created cluster configuration"
rescue => e
  puts "✗ Error: #{e.message}"
end

# Check native extension
if CassandraCpp.respond_to?(:native_loaded?)
  puts "✓ Native extension loaded: #{CassandraCpp.native_loaded?}"
end
```

Run the test:

```bash
ruby test_install.rb
```

Expected output:
```
Cassandra-CPP version: 2.0.0
Driver version: 2.16.2
✓ Successfully created cluster configuration
✓ Native extension loaded: true
```

## Next Steps

Now that you have Cassandra-CPP installed, proceed to:
- [Configuration](02_configuration.md) - Set up your cluster connection
- [Basic Usage](03_basic_usage.md) - Start using the driver
- [Troubleshooting](09_troubleshooting.md) - If you encounter any issues

## Getting Help

If you encounter installation issues:

1. Check the [Troubleshooting Guide](09_troubleshooting.md)
2. Search [existing issues](https://github.com/your-org/cassandra-cpp/issues)
3. Join our [Slack channel](https://ruby-cassandra.slack.com)
4. Create a new issue with:
   - Your OS and version
   - Ruby version (`ruby -v`)
   - Compiler version (`gcc --version` or `clang --version`)
   - Full error output
   - Steps to reproduce