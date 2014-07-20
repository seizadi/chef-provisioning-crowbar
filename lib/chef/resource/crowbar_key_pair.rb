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

require 'chef_metal'

class Chef::Resource::CrowbarKeyPair < Chef::Resource::LWRPBase
  self.resource_name = 'crowbar_key_pair'

  def initialize(*args)
    super
    @driver = run_context.chef_metal.current_driver
  end

  actions :create, :delete, :nothing
  default_action :create

  attribute :driver
  # Private key to use as input (will be generated if it does not exist)
  attribute :private_key_path, :kind_of => String
  # Public key to use as input (will be generated if it does not exist)
  attribute :public_key_path, :kind_of => String
  # List of parameters to the private_key resource used for generation of the key
  attribute :private_key_options, :kind_of => Hash

  # TODO what is the right default for this?
  attribute :allow_overwrite, :kind_of => [TrueClass, FalseClass], :default => false

  # Proc that runs after the resource completes.  Called with (resource, private_key, public_key)
  def after(&block)
    block ? @after = block : @after
  end
end
