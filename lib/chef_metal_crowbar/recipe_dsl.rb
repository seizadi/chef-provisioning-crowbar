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

require 'chef_metal_crowbar/crowbar_driver'
require 'chef/resource/crowbar_key_pair'
require 'chef/provider/crowbar_key_pair'

class Chef
  module DSL
    module Recipe
      def with_crowbar_driver(provider, driver_options = nil, &block)
        config = Cheffish::MergedConfig.new({ :driver_options => driver_options }, run_context.config)
        driver = ChefMetalCrowbar::CrowbarDriver.from_provider(provider, config)
        run_context.chef_metal.with_driver(driver, &block)
      end
    end
  end
end
