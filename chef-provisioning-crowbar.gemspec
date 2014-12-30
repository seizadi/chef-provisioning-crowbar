# Copyright 2014, Rob Hirschfeld
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

$:.unshift(File.dirname(__FILE__) + '/lib')
require 'chef/provisioning/crowbar_driver/version'

Gem::Specification.new do |s|
  s.name = 'chef-provisioning-crowbar'
  s.version = Chef::Provisioning::CrowbarDriver::VERSION
  s.platform = Gem::Platform::RUBY
  s.extra_rdoc_files = ['README.md', 'LICENSE' ]
  s.summary = 'Driver for creating Crowbar servers in Chef Provisioning.'
  s.license = 'Apache 2'
  s.description = 'Crowbar is an open-source, multi-purpose node deployment tool.'
  s.author = 'Judd Maltin'
  s.email = 'judd@newgoliath.com'
  s.homepage = 'https://github.com/newgoliath/chef-provisioning-crowbar'

  s.add_runtime_dependency 'chef', '~> 11.0'

  s.add_dependency 'chef-provisioning', '~> 0.15'
  s.add_dependency 'httparty', '~> 0'

  #s.add_development_dependency 'rspec'
  s.add_development_dependency 'rake', '~> 0'

  s.bindir       = "bin"
  s.executables  = %w( )

  s.require_path = 'lib'
  s.files = %w(Rakefile LICENSE README.md) + Dir.glob("{distro,lib,tasks,spec}/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }
end
