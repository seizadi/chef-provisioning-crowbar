# Copyright 2014, Rob Hirschfeld, Judd Maltin
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


require 'chef/provisioning'
with_driver 'crowbar'

with_chef_server 'https://192.168.124.10',
                 :client_name => 'metal',
                 :signing_key_filename => '/etc/chef/client.pem'

# Crowbar these days is defaulting to installing Centos-7.0
# on its slave nodes.
#
# To select other operating systems supported by your crowbar:
# see /opt/opencrowbar/core/crowbar.yml
# get target_os values from the os_support array
# You can add more.

# You can set your default OS for this recipe:
#with_machine_options crowbar_options: {
#                        'provisioner-target_os' => 'centos-6.5'
#}

# build one with an overridden OS
machine "chef-provisioning-example-#{rand(100)}" do
  machine_options :crowbar_options => { 'provisioner-target_os' => 'centos-7.0' }
end

