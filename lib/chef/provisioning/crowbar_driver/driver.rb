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

#require 'chef/mixin/shell_out'
require 'chef/provisioning/driver'
require 'chef/provisioning/machine/unix_machine'
require 'chef/provisioning/machine_spec'
require 'chef/provisioning/convergence_strategy/install_cached'
require 'chef/provisioning/transport/ssh'
require 'chef/provisioning/crowbar_driver/version'
require 'etc'
require 'time'
#require 'cheffish/merged_config'
require 'crowbar/core'

class Chef
module Provisioning
module CrowbarDriver

  class Driver < Chef::Provisioning::Driver


    ALLOCATE_DEPLOYMENT   = 'system'
    READY_DEPLOYMENT      = 'ready'
    TARGET_NODE_ROLE      = "crowbar-installed-node"
    API_BASE              = "/api/v2"

    def initialize(driver_url, config)
      super(driver_url, config)
      @crowbar = Crowbar.new
      #config[:private_key_paths] = [ "$HOME/.ssh/id_rsa" ]
      #config[:log_level] = :debug
    end
    
    # Passed in a driver_url, and a config in the format of Driver.config.
    def self.from_url(driver_url, config)
      Driver.new(driver_url, config)
    end

    def self.canonicalize_url(driver_url, config)
      [ driver_url, config ]
    end

    # Acquire a machine, generally by provisioning it.  Returns a Machine
    # object pointing at the machine, allowing useful actions like setup,
    # converge, execute, file and directory.

    def allocate_machine(action_handler, machine_spec, machine_options)

      @crowbar.log_level(config[:log_level])
      
      if machine_spec.location
        if !@crowbar.node_exists?(machine_spec.location['server_id'])
          # It doesn't really exist
          action_handler.perform_action "Machine #{machine_spec.location['server_id']} does not really exist.  Recreating ..." do
            machine_spec.location = nil
          end
        end
      end

      if !machine_spec.location
        action_handler.perform_action "Crowbar: #{@crowbar} Creating server #{machine_spec.name} with options #{machine_options}" do
          # TODO: Make sure SSH keys are found locally here?  Or in allocate_node?
          # get ssh pubkey from current user
          #result = shell_out("cat ~/.ssh/id_rsa.pub", :cwd => '$HOME')
          #sshkey = result.stdout
          #action_handler.report_progress "sshpubkey on admin server #{sshkey}\n"
          # put it on the crowbar server provisioner
          #@crowbar.add_sshkey(result.stdout)
          
          server = allocate_node(machine_spec.name, machine_options, action_handler)
          server_id = server["id"]
          debug "allocate server_id = #{server_id}"
          machine_spec.location = {
            'driver_url' => driver_url,
            'driver_version' => Chef::Provisioning::CrowbarDriver::VERSION,
            'server_id' => server_id,
            'node_role_id' => server["node_role_id"]
           # 'bootstrap_key' => sshkey
          }
        end
      end
    end

    # Ready a machine moves the machine from the System deployment
    # to the Ready deployment.  Default Ready deployment is named 'ready'
    # but will pick up machine_configs that match
    def ready_machine(action_handler, machine_spec, machine_options)
      debug machine_spec.location
 
      server_id = machine_spec.location['server_id']
      unless @crowbar.node_alive?(server_id)
        action_handler.perform_action "Powering up machine #{server_id}" do
          @crowbar.power(server_id, "on")
        end
      end

      nr_id = machine_spec.location['node_role_id']

      action_handler.report_progress "Awaiting ready machine..."
      action_handler.perform_action "done waiting for machine id: #{server_id}" do
        loop do 
          break if @crowbar.node_ready(server_id,nr_id)
          sleep 5
        end 
        action_handler.report_progress "waited for machine - machine is ready. machine id: #{server_id}" 
      end

      # set the machine to "reserved" to take control away from Crowbar
      node = @crowbar.node(server_id)
      node['available'] = false
      @crowbar.set_node(server_id, node)

      # Return the Machine object
      machine_for(machine_spec, machine_options)
    end

    def machine_for(machine_spec, machine_options)
      ssh_options = {
        :auth_methods => ['publickey'],
      }
      server_id = machine_spec.location['server_id']
      node_admin_addresses = @crowbar.node_attrib(server_id, 'network-admin_addresses')
      node_ipv4_admin_net_ip = node_admin_addresses['value'][0].split('/')[0]
      node_ipv4_admin_net_ip = node_admin_addresses['value'][0].split('/')[0]
      #node_ipv6_admin_net_ip = node_admin_addresses['value'][1]
      
      transport = Chef::Provisioning::Transport::SSH.new(node_ipv4_admin_net_ip, 'root', ssh_options, {}, config)
      convergence_strategy = Chef::Provisioning::ConvergenceStrategy::InstallCached.new(machine_options[:convergence_options], config)
      Chef::Provisioning::Machine::UnixMachine.new(machine_spec, transport, convergence_strategy)
    end

    def create_ssh_transport(machine_spec)
      crowbar_ssh_config = crowbar_ssh_config_for(machine_spec)
      hostname = crowbar_ssh_config['HostName']
      username = crowbar_ssh_config['User']
      ssh_options = {
        :port => '22',
        :auth_methods => ['publickey'],
        #:user_known_hosts_file => crowbar_ssh_config['UserKnownHostsFile'],
        :paranoid => false, #yes_or_no(vagrant_ssh_config['StrictHostKeyChecking']),
        :keys => [ '$HOME/.ssh/id_rsa' ],
        :keys_only => true
      }
      Chef::Provisioning::Transport::SSH.new(hostname, username, ssh_options, options, config) end

    def ensure_deployment(to_deployment)
      unless @crowbar.deployment_exists?(to_deployment)
          @crowbar.deployment_create(to_deployment)
          debug("Crowbar deployment '#{to_deployment}' does not exist... creating...")
      end
    end

    def get_non_admin_nodes(names=[])
      # get available nodes
      from_deployment = ALLOCATE_DEPLOYMENT
      pool = @crowbar.non_admin_nodes_in_deployment(from_deployment)
      raise "No available non-admin nodes in pool '#{from_deployment}'" if !pool || pool.size == 0
      #action_handler.report_progress "Pool size: #{pool.size}"
      # make sure node name isn't taken
      good_nodes = []
      names.each do |name|
        pool.each do |node|
          if node['alias'] == name
            debug "Node #{name} already exists, skipping."
            break
          end
          good_nodes << node
        end
      end
      return good_nodes
    end


    def set_node_and_bind_noderole(node,name,role,to_deployment,crowbar_options={})
      debug("set_node_foundling #{node}")
      node["alias"] = name
      node["deployment"] = to_deployment
      raise "Setting node #{node["alias"]} to deployment \"#{to_deployment}\" failed." unless @crowbar.set_node(node["id"], node)
      #action_handler.report_progress "Crowbar node\'s deployment attirbute set to \"#{to_deployment}\"\n"
      

      # bind the NodeRole if missing (eventually set the OS property)
      bind = {:node=>node["id"], :role=>role, :deployment=>to_deployment}
      # blindly add node role > we need to make this smarter and skip if unneeded
      # query node for all its noderoles and skip if noderole is in finished state
      node["node_role_id"] = @crowbar.bind_node_role(bind)
      #action_handler.report_progress "Crowbar node #{node["id"]} noderole bound to #{TARGET_NODE_ROLE} deployment #{to_deployment} as noderole #{node["node_role_id"]}\n"

      # set crowbar_options.  they're attribs in crowbar
      crowbar_options.each do |attrib, value|
        #attribs = {  "provisioner-target_os" => machine_options[:crowbar_options]['provisioner-target_os'] }
        @crowbar.set_node_attrib( node["id"], attrib, value )
      end
      node
    end
    
    # debug messages
    def debug(msg)
      Chef::Log.debug msg
    end

    # Allocate many machines simultaneously
    def allocate_machines(action_handler, specs_and_options, parallelizer)
      to_deployment = READY_DEPLOYMENT

      # check for ready deployment
      ensure_deployment(to_deployment)
      # can the deployment be set to proposed?
      @crowbar.propose_deployment(to_deployment)

      #private_key = get_private_key('bootstrapkey')
      servers = []
      server_names = []
      specs_and_options.each do |machine_spec, machine_options|
        if !machine_spec.location
          servers << [ machine_spec.name, machine_options ]
          server_names << machine_spec.name
          # skip name collisions
          # add nodes to ready deployment
          # Tell the cloud API to spin them all up at once
          action_handler.perform_action "Allocating servers #{server_names.join(',')} from the cloud" do
            role = TARGET_NODE_ROLE
            node = get_non_admin_nodes([machine_spec.name])[0]
            server = set_node_and_bind_noderole(node,machine_spec.name,role,to_deployment,machine_options[:crowbar_options])
            server_id = server["id"]
            debug "allocate server_id = #{server_id}"
            machine_spec.location = {
              'driver_url' => driver_url,
              'driver_version' => Chef::Provisioning::CrowbarDriver::VERSION,
              'server_id' => server_id,
              'node_role_id' => server["node_role_id"]
            }
          end
        end
      end

        
      # commit deployment
      @crowbar.commit_deployment(to_deployment) 
    end

    # follow getready process to allocate nodes
    def allocate_node(name, machine_options, action_handler)

      role = TARGET_NODE_ROLE
      to_deployment = READY_DEPLOYMENT
      
      ensure_deployment(to_deployment)

      @crowbar.propose_deployment(to_deployment)

      my_node = get_non_admin_nodes([name])[0]
      #puts(my_node)
      set_node_and_bind_noderole(my_node,name,role,to_deployment,machine_options[:crowbar_options])

      @crowbar.commit_deployment(to_deployment)

      # at this point Crowbar will bring up the node in the background
      # we can return the node handle to the user
      my_node

    end
    private

  end # Class
end
end # Module
end
