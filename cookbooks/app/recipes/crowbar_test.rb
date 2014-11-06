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


# Crowbar these days is defaulting to installing Centos-7.0
# on its slave nodes.
#
# To select other operating systems supported by your crowbar:
# see /opt/opencrowbar/core/crowbar.yml
# get target_os values from the os_support array
# You can add more.

# set your default OS for this recipe:
with_machine_options crowbar_options: {
                        'provisioner-target_os' => 'centos-6.5'
}

# build sample servers

# build a few with defaults from crowbar_options, above.
num_servers = 1
1.upto(num_servers) do |i|
  machine "chef-provisioning-#{random}" do
  end 
end

# build one with an overrided OS

machine "chef-provisioning-another-#{random}" do
  machine_options :crowbar_options => { 'provisioner-target_os' => 'centos-7.0' }
end


# TODO:
#with_chef_server 'https://127.0.0.1:443',
#                 :client_name => 'crowbar',
#                 :signing_key_filename => '/root/.chef/crowbar.pem'
 
#with_machine_options :crowbar_options => { 
#  'bootstrap_options' => { :key_name => 'crowbar', os: 'ubuntu-12.04' } 
#} 
    #chef_environment 'test'
    #recipe 'mydb'
    #tag 'mydb_master'
