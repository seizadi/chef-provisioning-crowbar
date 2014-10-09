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


# Notes
# sudo /opt/chef/embedded/bin/gem install chef-zero
# sudo /opt/chef/embedded/bin/gem install /opt/opencrowbar/chef-metal/chef-metal-crowbar
# run with chef-client -z 

require 'chef_metal'

with_driver 'crowbar'
 
num_servers = 1
 
# build sample servers
1.upto(num_servers) do |i|
  random = rand(10 ** 4)
  machine "chef-metal-#{random}" do
    #chef_environment 'test'
    #recipe 'mydb'
    #tag 'mydb_master'
  end 
end






# TODO:
#with_chef_server 'https://127.0.0.1:443',
#                 :client_name => 'crowbar',
#                 :signing_key_filename => '/root/.chef/crowbar.pem'
 
#with_machine_options :crowbar_options => { 
#  'bootstrap_options' => { :key_name => 'crowbar', os: 'ubuntu-12.04' } 
#} 
