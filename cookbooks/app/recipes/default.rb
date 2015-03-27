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

require 'chef-provisioning'
   
with_driver 'crowbar:http://10.49.12.20:3000'
with_driver_options :crowbar_user => 'crowbar', :driver_config => 'crowbar'

random = rand(10 ** 4) 
 
# build a sample server
# build one with an overridden OS
machine "chef-provisioning-example-#{rand(100)}" do
  machine_options :crowbar_options => { 'provisioner-target_os' => 'centos-7.0' }
end