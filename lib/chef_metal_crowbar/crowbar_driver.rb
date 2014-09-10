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

require 'chef_metal/driver'
require 'chef_metal/machine/windows_machine'
require 'chef_metal/machine/unix_machine'
require 'chef_metal/machine_spec'
require 'chef_metal/convergence_strategy/install_msi'
require 'chef_metal/convergence_strategy/install_sh'
require 'chef_metal/convergence_strategy/install_cached'
require 'chef_metal/convergence_strategy/no_converge'
require 'chef_metal/transport/ssh'
require 'chef_metal_crowbar/version'
require 'etc'
require 'time'
require 'cheffish/merged_config'
require 'chef_metal_crowbar/recipe_dsl'
require 'crowbar/core'

module ChefMetalCrowbar

  class CrowbarDriver < ChefMetal::Driver

    ALLOCATE_DEPLOYMENT   = 'system'
    READY_DEPLOYMENT      = 'ready'
    TARGET_NODE_ROLE      = "crowbar-managed-node"
    KEY_ATTRIB            = "chef-server_admin_client_key"
    API_BASE              = "/api/v2"


    def initialize(driver_url, config)
      super(driver_url, config)
      @crowbar = Crowbar.new
    end
    
    # Passed in a driver_url, and a config in the format of Driver.config.
    def self.from_url(driver_url, config)
      CrowbarDriver.new(driver_url, config)
    end

    def self.canonicalize_url(driver_url, config)
      [ driver_url, config ]
    end

    def crowbar_api
      # relies on url & driver_config from Driver superclass
      scheme, crowbar_url = driver_url.split(':', 2)
      #Core.connect crowbar_url, config
    end

    # Acquire a machine, generally by provisioning it.  Returns a Machine
    # object pointing at the machine, allowing useful actions like setup,
    # converge, execute, file and directory.

    def allocate_machine(action_handler, machine_spec, machine_options)
      
      if machine_spec.location
        if !node_exists?(machine_spec.location['server_id'])
          # It doesn't really exist
          action_handler.perform_action "Machine #{machine_spec.location['server_id']} does not really exist.  Recreating ..." do
            machine_spec.location = nil
          end
        end
      end

      if !machine_spec.location
        action_handler.perform_action "Crowbar: #{@crowbar.methods} Creating server #{machine_spec.name} with options #{machine_options}" do
          nil
        end
        action_handler.perform_action "Crowbar: #{@crowbar} Creating server #{machine_spec.name} with options #{machine_options}" do
          server = allocate_node(machine_spec.name, machine_options)
          server_id = server["id"]
          machine_spec.location = {
            'driver_url' => driver_url,
            'driver_version' => ChefMetalCrowbar::VERSION,
            'server_id' => server_id,
            'bootstrap_key' => @crowbar.ssh_private_key(server_id)
          }
        end
      end
    end

    def ready_machine(action_handler, machine_spec, machine_options)
      server_id = machine_spec.location['server_id']
      server = @crowbar.node(server_id)
      if server["alive"] == 'false'
        action_handler.perform_action "Powering up machine #{server_id}" do
          @crowbar.power(server_id, "on")
        end
      end

      if server["state"] != 0
        action_handler.perform_action "wait for machine #{server_id}" do
          @crowbar.node_status(server_id, 0)
          #crowbar_api.wait_for_machine_to_have_status(server_id, 0)
        end
      end

      # Return the Machine object
      machine_for(machine_spec, machine_options)
    end

    def machine_for(machine_spec, machine_options)
      server_id = machine_spec.location['server_id']
      ssh_options = {
        :auth_methods => ['publickey'],
        :keys => [ get_key('bootstrapkey') ],
      }
      transport = ChefMetal::Transport::SSHTransport.new(server_id, ssh_options, {}, config)
      convergence_strategy = ChefMetal::ConvergenceStrategy::InstallCached.new(machine_options[:convergence_options])
      ChefMetal::Machine::UnixMachine.new(machine_spec, transport, convergence_strategy)
    end

    private



    # follow getready process to allocate nodes
    def allocate_node(name, machine_options)

      # get available nodes
      from_deployment = ALLOCATE_DEPLOYMENT
      raise "Crowbar deployment '#{from_deployment}' does not exist" unless @crowbar.deployment_exists?(from_deployment)
      raise "No non-admin nodes in deployment" unless pool = @crowbar.non_admin_nodes_in_deployment(from_deployment)
      
      raise "No available nodes in pool '#{from_deployment}'" if !pool || pool.size == 0

      # assign a node from pool
      node = pool[0]

      # prepare for moving by setting the deployment to proposed
      to_deployment = READY_DEPLOYMENT
      raise "Error setting deployment to proposed " unless @crowbar.propose_deployment(to_deployment)

      # set alias (name) and reserve
      node["alias"] = name
      node["deployment"] = to_deployment
      raise "Setting node data failed." unless @crowbar.set_node(node["id"], node)

      # bind the OS NodeRole if missing (eventually set the OS property)
      bind = {:node=>node["id"], :role=>TARGET_NODE_ROLE, :deployment=>to_deployment}
      # blindly add node role > we need to make this smarter and skip if unneeded
      @crowbar.bind_noderole(bind)

      # commit the deployment
      @crowbar.commit_deployment(to_deployment)
      #put(driver_url + API_BASE + "deployments/#{to_deployment}/commit")

      # at this point Crowbar will bring up the node in the background
      # we can return the node handle to the user
      node["name"]

    end
    
    # debug messages
    def debug(msg)
      Chef::Log.debug msg
    end


  end
end
