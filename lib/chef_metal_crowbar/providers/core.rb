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

# crowbar:core:https://[url]/api/v2/
module ChefMetalCrowbar
  module Providers
    class Core < ChefMetalCrowbar::CrowbarDriver

      ChefMetalCrowbar::CrowbarDriver.register_provider_class('core', ChefMetalCrowbar::Providers::Base)

      def creator
        compute_options[:username]
      end

      def self.compute_options_for(provider, id, config)
        new_compute_options = {}
        new_compute_options[:provider] = provider
        new_config = { :driver_options => { :compute_options => new_compute_options }}
        new_defaults = {
          :driver_options => { :compute_options => {} },
          :machine_options => { :bootstrap_options => {} }
        }
        result = Cheffish::MergedConfig.new(new_config, config, new_defaults)

        new_compute_options[:url] = id if (id && id != '')
        credential = Crowbar.credentials

        new_compute_options[:username] ||= credential[:username]
        new_compute_options[:password] ||= credential[:password]
        new_compute_options[:url] ||= credential[:url]

        id = result[:driver_options][:compute_options][:url]

        [result, id]
      end

    end
  end
end
