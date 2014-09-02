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
    include Crowbar

    AVAILABLE_DEPLOYMENT  = 'available'
    RESERVED_DEPLOYMENT   = 'reserved'
    TARGET_NODE_ROLE      = "crowbar-managed-node"
    KEY_ATTRIB            = "chef-server_admin_client_key"

    # Passed in a driver_url, and a config in the format of Driver.config.
    def self.from_url(driver_url, config)
      CrowbarDriver.new(driver_url, config)
    end

    def self.canonicalize_url(driver_url, config)
      [ "crowbar:abcd", config ]
    end

    def initialize(driver_url, config)
      super(driver_url, config)
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
      Core.go crowbar_url
#
#      # If the server does not exist, create it
#      create_servers(action_handler, { machine_spec => machine_options }, Chef::ChefFS::Parallelizer.new(0))
#      machine_spec
    end

    def allocate_machine(action_handler, machine_spec, machine_options)
      if !crowbar_api.node_exists?(machine_spec.location['server_id'])
        # It doesn't really exist
        action_handler.perform_action "Machine #{machine_spec.location['server_id']} does not really exist.  Recreating ..." do
          machine_spec.location = nil
        end
      end
      if !machine_spec.location
        action_handler.perform_action "Creating server #{machine_spec.name} with options #{machine_options}" do
          server = crowbar_api.allocate_server(machine_spec.name, machine_options)
          server_id = server["id"]
          machine_spec.location = {
            'driver_url' => driver_url,
            'driver_version' => ChefMetalCrowbar::VERSION,
            'server_id' => server_id,
            'bootstrap_key' => crowbar_api.ssh_private_key(server_id)
          }
        end
      end
    end

    def ready_machine(action_handler, machine_spec, machine_options)
      server_id = machine_spec.location['server_id']
      server = crowbar_api.node(server_id)
      if server["alive"] == 'false'
        action_handler.perform_action "Powering up machine #{server_id}" do
          crowbar_api.power(server_id, "on")
        end
      end

      if server["state"] != 0
        action_handler.perform_action "wait for machine #{server_id}" do
          crowbar_api.wait_for_machine_to_have_status(server_id, 0)
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


    # hit node API to see if node exists (code 200 only)
    def node_exists?(name)
      exists?("node", name)
    end

    # hit deployment API to see if deployment exists (code 200 only)
    def deployment_exists?(name)
      exists?("deployment", name)
    end

    # using the attibutes, get the key
    def ssh_private_key(name)
      get(driver_url + API_BASE + "nodes/#{name}/attribs/#{KEY_ATTRIB}")
    end

    # follow getready process to allocate nodes
    def allocate_node(name, machine_options)

      # get available nodes
      from_deployment = AVAILABLE_DEPLOYMENT
      raise "Available Pool '#{from_deployment} does not exist" unless deployment_exists?(from_deployment)
      pool = get(driver_url + API_BASE + "deployments/#{from_deployment}/nodes")
      raise "No available nodes in pool #{from_deployment}" if pool.size == 0

      # assign node from pool
      node = pool[0]

      # prepare for moving by moving the deployment to proposed
      to_deployment = RESERVED_DEPLOYMENT
      put(driver_url + API_BASE + "deployments/#{to_deployment}/propose")

      # set alias (name) and reserve
      node["alias"] = name
      node["deployment"] = to_deployment
      put(driver_url + API_BASE + "nodes/#{node["id"]}", node)

      # bind the OS NodeRole if missing (eventually set the OS property)
      bind = {:node=>node["id"], :role=>TARGET_NODE_ROLE, :deployment=>to_deployment}
      # blindly add node role > we need to make this smarter and skip if unneeded
      post(driver_url + API_BASE + "node_roles", bind)

      # commit the deployment
      put(driver_url + API_BASE + "deployments/#{to_deployment}/commit")

      # at this point Crowbar will bring up the node in the background
      # we can return the node handle to the user
      node["name"]

    end

    def node(name)
      get(driver_url + API_BASE + "nodes/#{name}")
    end

    def power(name, action="on")
      put(driver_url + API_BASE + "nodes/#{name}/power?poweraction=#{action}")
    end

    def wait_for_machine_to_have_status(name, target_state)
      node(name)["state"] == target_state
    end

    # debug messages
    def debug(msg)
      Chef::Log.debug msg
    end


#   include Chef::Mixin::ShellOut

#     DEFAULT_OPTIONS = {
#       :create_timeout => 180,
#       :start_timeout => 180,
#       :ssh_timeout => 20
#     }

#     class << self
#       alias :__new__ :new

#       def inherited(klass)
#         class << klass
#           alias :new :__new__
#         end
#       end
#     end

#     @@registered_provider_classes = {}
#     def self.register_provider_class(name, driver)
#       @@registered_provider_classes[name] = driver
#     end

#     def self.provider_class_for(provider)
#       require "chef_metal_crowbar/providers/#{provider.downcase}"
#       @@registered_provider_classes[provider]
#     end

#     def self.new(driver_url, config)
#       provider = driver_url.split(':')[1]
#       provider_class_for(provider).new(driver_url, config)
#     end

#     def self.canonicalize_url(driver_url, config)
#       _, provider, id = driver_url.split(':', 3)
#       config, id = provider_class_for(provider).compute_options_for(provider, id, config)
#       [ "crowbar:#{provider}:#{id}", config ]
#     end

#     # Passed in a config which is *not* merged with driver_url (because we don't
#     # know what it is yet) but which has the same keys
#     def self.from_provider(provider, config)
#       provider ||= "core"
#       # Figure out the options and merge them into the config
#       config, id = provider_class_for(provider).compute_options_for(provider, nil, config)

#       driver_url = "crowbar:#{provider}:#{id}"

#       ChefMetal.driver_for_url(driver_url, config)
#     end

#     def compute_options
#       driver_options[:compute_options].to_hash || {}
#     end

#     def provider
#       compute_options[:provider]
#     end

#     # Acquire a machine, generally by provisioning it.  Returns a Machine
#     # object pointing at the machine, allowing useful actions like setup,
#     # converge, execute, file and directory.
#     def allocate_machine(action_handler, machine_spec, machine_options)
#       # If the server does not exist, create it
#       create_servers(action_handler, { machine_spec => machine_options }, Chef::ChefFS::Parallelizer.new(0))
#       machine_spec
#     end

#     def allocate_machines(action_handler, specs_and_options, parallelizer)
#       create_servers(action_handler, specs_and_options, parallelizer) do |machine_spec, server|
#         yield machine_spec
#       end
#       specs_and_options.keys
#     end

#     def ready_machine(action_handler, machine_spec, machine_options)
#       server = server_for(machine_spec)
#       if server.nil?
#         raise "Machine #{machine_spec.name} does not have a server associated with it, or server does not exist."
#       end

#       # Attach floating IPs if necessary
#       attach_floating_ips(action_handler, machine_spec, machine_options, server)

#       # Start the server if needed, and wait for it to start
#       start_server(action_handler, machine_spec, server)
#       wait_until_ready(action_handler, machine_spec, machine_options, server)
#       begin
#         wait_for_transport(action_handler, machine_spec, machine_options, server)
#       rescue Crowbar::Errors::TimeoutError
#         # Only ever reboot once, and only if it's been less than 10 minutes since we stopped waiting
#         if machine_spec.location['started_at'] || remaining_wait_time(machine_spec, machine_options) < -(10*60)
#           raise
#         else
#           # Sometimes (on EC2) the machine comes up but gets stuck or has
#           # some other problem.  If this is the case, we restart the server
#           # to unstick it.  Reboot covers a multitude of sins.
#           Chef::Log.warn "Machine #{machine_spec.name} (#{server.id} on #{driver_url}) was started but SSH did not come up.  Rebooting machine in an attempt to unstick it ..."
#           restart_server(action_handler, machine_spec, server)
#           wait_until_ready(action_handler, machine_spec, machine_options, server)
#           wait_for_transport(action_handler, machine_spec, machine_options, server)
#         end
#       end

#       machine_for(machine_spec, machine_options, server)
#     end

#     # Connect to machine without acquiring it
#     def connect_to_machine(machine_spec, machine_options)
#       machine_for(machine_spec, machine_options)
#     end

#     def destroy_machine(action_handler, machine_spec, machine_options)
#       server = server_for(machine_spec)
#       if server
#         action_handler.perform_action "destroy machine #{machine_spec.name} (#{machine_spec.location['server_id']} at #{driver_url})" do
#           server.destroy
#           machine_spec.location = nil
#         end
#       end
#       strategy = convergence_strategy_for(machine_spec, machine_options)
#       strategy.cleanup_convergence(action_handler, machine_spec)
#     end

#     def stop_machine(action_handler, machine_spec, machine_options)
#       server = server_for(machine_spec)
#       if server
#         action_handler.perform_action "stop machine #{machine_spec.name} (#{server.id} at #{driver_url})" do
#           server.stop
#         end
#       end
#     end

#     def compute
#       @compute ||= Crowbar::Compute.new(compute_options)
#     end

#     # Not meant to be part of public interface
#     def transport_for(machine_spec, machine_options, server)
#       # TODO winrm
#       create_ssh_transport(machine_spec, machine_options, server)
#     end

#     protected

#     def option_for(machine_options, key)
#       machine_options[key] || DEFAULT_OPTIONS[key]
#     end

#     def creator
#       raise "unsupported provider #{provider} (please implement #creator)"
#     end

#     def create_servers(action_handler, specs_and_options, parallelizer, &block)
#       specs_and_servers = servers_for(specs_and_options.keys)

#       # Get the list of servers which exist, segmented by their bootstrap options
#       # (we will try to create a set of servers for each set of bootstrap options
#       # with create_many)
#       by_bootstrap_options = {}
#       specs_and_options.each do |machine_spec, machine_options|
#         server = specs_and_servers[machine_spec]
#         if server
#           if %w(terminated archive).include?(server.state) # Can't come back from that
#             Chef::Log.warn "Machine #{machine_spec.name} (#{server.id} on #{driver_url}) is terminated.  Recreating ..."
#           else
#             yield machine_spec, server if block_given?
#             next
#           end
#         elsif machine_spec.location
#           Chef::Log.warn "Machine #{machine_spec.name} (#{machine_spec.location['server_id']} on #{driver_url}) no longer exists.  Recreating ..."
#         end

#         bootstrap_options = bootstrap_options_for(action_handler, machine_spec, machine_options)
#         by_bootstrap_options[bootstrap_options] ||= []
#         by_bootstrap_options[bootstrap_options] << machine_spec
#       end

#       # Create the servers in parallel
#       parallelizer.parallelize(by_bootstrap_options) do |bootstrap_options, machine_specs|
#         machine_description = if machine_specs.size == 1
#           "machine #{machine_specs.first.name}"
#         else
#           "machines #{machine_specs.map { |s| s.name }.join(", ")}"
#         end
#         description = [ "creating #{machine_description} on #{driver_url}" ]
#         bootstrap_options.each_pair { |key,value| description << "  #{key}: #{value.inspect}" }
#         action_handler.report_progress description

#         if action_handler.should_perform_actions
#           # Actually create the servers
#           create_many_servers(machine_specs.size, bootstrap_options, parallelizer) do |server|

#             # Assign each one to a machine spec
#             machine_spec = machine_specs.pop
#             machine_options = specs_and_options[machine_spec]
#             machine_spec.location = {
#               'driver_url' => driver_url,
#               'driver_version' => ChefMetalCrowbar::VERSION,
#               'server_id' => server.id,
#               'creator' => creator,
#               'allocated_at' => Time.now.to_i
#             }
#             machine_spec.location['key_name'] = bootstrap_options[:key_name] if bootstrap_options[:key_name]
#             %w(is_windows ssh_username sudo use_private_ip_for_ssh ssh_gateway).each do |key|
#               machine_spec.location[key] = machine_options[key.to_sym] if machine_options[key.to_sym]
#             end
#             action_handler.performed_action "machine #{machine_spec.name} created as #{server.id} on #{driver_url}"

#             yield machine_spec, server if block_given?
#           end

#           if machine_specs.size > 0
#             raise "Not all machines were created by create_many_machines!"
#           end
#         end
#       end.to_a
#     end

#     def create_many_servers(num_servers, bootstrap_options, parallelizer)
#       parallelizer.parallelize(1.upto(num_servers)) do |i|
#         server = compute.servers.create(bootstrap_options)
#         yield server if block_given?
#         server
#       end.to_a
#     end

#     def start_server(action_handler, machine_spec, server)
#       # If it is stopping, wait for it to get out of "stopping" transition state before starting
#       if server.state == 'stopping'
#         action_handler.report_progress "wait for #{machine_spec.name} (#{server.id} on #{driver_url}) to finish stopping ..."
#         server.wait_for { server.state != 'stopping' }
#         action_handler.report_progress "#{machine_spec.name} is now stopped"
#       end

#       if server.state == 'stopped'
#         action_handler.perform_action "start machine #{machine_spec.name} (#{server.id} on #{driver_url})" do
#           server.start
#           machine_spec.location['started_at'] = Time.now.to_i
#         end
#         machine_spec.save(action_handler)
#       end
#     end

#     def restart_server(action_handler, machine_spec, server)
#       action_handler.perform_action "restart machine #{machine_spec.name} (#{server.id} on #{driver_url})" do
#         server.reboot
#         machine_spec.location['started_at'] = Time.now.to_i
#       end
#       machine_spec.save(action_handler)
#     end

#     def remaining_wait_time(machine_spec, machine_options)
#       if machine_spec.location['started_at']
#         timeout = option_for(machine_options, :start_timeout) - (Time.now.utc - parse_time(machine_spec.location['started_at']))
#       else
#         timeout = option_for(machine_options, :create_timeout) - (Time.now.utc - parse_time(machine_spec.location['allocated_at']))
#       end
#       timeout > 0 ? timeout : 0.01
#     end

#     def parse_time(value)
#       if value.is_a?(String)
#         Time.parse(value)
#       else
#         Time.at(value)
#       end
#     end

#     def wait_until_ready(action_handler, machine_spec, machine_options, server)
#       if !server.ready?
#         if action_handler.should_perform_actions
#           action_handler.report_progress "waiting for #{machine_spec.name} (#{server.id} on #{driver_url}) to be ready ..."
#           server.wait_for(remaining_wait_time(machine_spec, machine_options)) { ready? }
#           action_handler.report_progress "#{machine_spec.name} is now ready"
#         end
#       end
#     end

#     def wait_for_transport(action_handler, machine_spec, machine_options, server)
#       transport = transport_for(machine_spec, machine_options, server)
#       if !transport.available?
#         if action_handler.should_perform_actions
#           action_handler.report_progress "waiting for #{machine_spec.name} (#{server.id} on #{driver_url}) to be connectable (transport up and running) ..."

#           _self = self

#           server.wait_for(remaining_wait_time(machine_spec, machine_options)) do
#             transport.available?
#           end
#           action_handler.report_progress "#{machine_spec.name} is now connectable"
#         end
#       end
#     end

#     def attach_floating_ips(action_handler, machine_spec, machine_options, server)
#       # TODO this is not particularly idempotent. OK, it is not idempotent AT ALL.  Fix.
#       if option_for(machine_options, :floating_ip_pool)
#         Chef::Log.info 'Attaching IP from pool'
#         action_handler.perform_action "attach floating IP from #{option_for(machine_options, :floating_ip_pool)} pool" do
#           attach_ip_from_pool(server, option_for(machine_options, :floating_ip_pool))
#         end
#       elsif option_for(machine_options, :floating_ip)
#         Chef::Log.info 'Attaching given IP'
#         action_handler.perform_action "attach floating IP #{option_for(machine_options, :floating_ip)}" do
#           attach_ip(server, option_for(machine_options, :allocation_id), option_for(machine_options, :floating_ip))
#         end
#       end
#     end

#     # Attach IP to machine from IP pool
#     # Code taken from kitchen-openstack driver
#     #    https://github.com/test-kitchen/kitchen-openstack/blob/master/lib/kitchen/driver/openstack.rb#L196-L207
#     def attach_ip_from_pool(server, pool)
#       @ip_pool_lock ||= Mutex.new
#       @ip_pool_lock.synchronize do
#         Chef::Log.info "Attaching floating IP from <#{pool}> pool"
#         free_addrs = compute.addresses.collect do |i|
#           i.ip if i.fixed_ip.nil? and i.instance_id.nil? and i.pool == pool
#         end.compact
#         if free_addrs.empty?
#           raise ActionFailed, "No available IPs in pool <#{pool}>"
#         end
#         attach_ip(server, free_addrs[0])
#       end
#     end

#     # Attach given IP to machine
#     # Code taken from kitchen-openstack driver
#     #    https://github.com/test-kitchen/kitchen-openstack/blob/master/lib/kitchen/driver/openstack.rb#L209-L213
#     def attach_ip(server, allocation_id, ip)
#       Chef::Log.info "Attaching floating IP <#{ip}>"
#       compute.associate_address(:instance_id => server.id,
#                                 :allocation_id => allocation_id,
#                                 :public_ip => ip)
#     end

#     def symbolize_keys(options)
#       options.inject({}) do |result,(key,value)|
#         result[key.to_sym] = value
#         result
#       end
#     end

#     def server_for(machine_spec)
#       if machine_spec.location
#         compute.servers.get(machine_spec.location['server_id'])
#       else
#         nil
#       end
#     end

#     def servers_for(machine_specs)
#       result = {}
#       machine_specs.each do |machine_spec|
#         if machine_spec.location
#           if machine_spec.location['driver_url'] != driver_url
#             raise "Switching a machine's driver from #{machine_spec.location['driver_url']} to #{driver_url} for is not currently supported!  Use machine :destroy and then re-create the machine on the new driver."
#           end
#           result[machine_spec] = compute.servers.get(machine_spec.location['server_id'])
#         else
#           result[machine_spec] = nil
#         end
#       end
#       result
#     end

#     @@metal_default_lock = Mutex.new

#     def overwrite_default_key_willy_nilly(action_handler)
#       driver = self
#       updated = @@metal_default_lock.synchronize do
#         ChefMetal.inline_resource(action_handler) do
#           crowbar_key_pair 'metal_default' do
#             driver driver
#             allow_overwrite true
#           end
#         end
#       end
#       if updated
#         # Only warn the first time
#         Chef::Log.warn("Using metal_default key, which is not shared between machines!  It is recommended to create an AWS key pair with the crowbar_key_pair resource, and set :bootstrap_options => { :key_name => <key name> }")
#       end
#       'metal_default'
#     end

#     def bootstrap_options_for(action_handler, machine_spec, machine_options)
#       bootstrap_options = symbolize_keys(machine_options[:bootstrap_options] || {})

#       bootstrap_options[:tags]  = default_tags(machine_spec, bootstrap_options[:tags] || {})

#       bootstrap_options[:name] ||= machine_spec.name

#       bootstrap_options
#     end

#     def default_tags(machine_spec, bootstrap_tags = {})
#       tags = {
#           'Name' => machine_spec.name,
#           'BootstrapId' => machine_spec.id,
#           'BootstrapHost' => Socket.gethostname,
#           'BootstrapUser' => Etc.getlogin
#       }
#       # User-defined tags override the ones we set
#       tags.merge(bootstrap_tags)
#     end

#     def machine_for(machine_spec, machine_options, server = nil)
#       server ||= server_for(machine_spec)
#       if !server
#         raise "Server for node #{machine_spec.name} has not been created!"
#       end

#       if machine_spec.location['is_windows']
#         ChefMetal::Machine::WindowsMachine.new(machine_spec, transport_for(machine_spec, machine_options, server), convergence_strategy_for(machine_spec, machine_options))
#       else
#         ChefMetal::Machine::UnixMachine.new(machine_spec, transport_for(machine_spec, machine_options, server), convergence_strategy_for(machine_spec, machine_options))
#       end
#     end

#     def convergence_strategy_for(machine_spec, machine_options)
#       # Defaults
#       if !machine_spec.location
#         return ChefMetal::ConvergenceStrategy::NoConverge.new(machine_options[:convergence_options], config)
#       end

#       if machine_spec.location['is_windows']
#         ChefMetal::ConvergenceStrategy::InstallMsi.new(machine_options[:convergence_options], config)
#       elsif machine_options[:cached_installer] == true
#         ChefMetal::ConvergenceStrategy::InstallCached.new(machine_options[:convergence_options], config)
#       else
#         ChefMetal::ConvergenceStrategy::InstallSh.new(machine_options[:convergence_options], config)
#       end
#     end

#     def ssh_options_for(machine_spec, machine_options, server)
#       result = {
# # TODO create a user known hosts file
# #          :user_known_hosts_file => vagrant_ssh_config['UserKnownHostsFile'],
# #          :paranoid => true,
#         :auth_methods => [ 'publickey' ],
#         :keys_only => true,
#         :host_key_alias => "#{server.id}.#{provider}"
#       }.merge(machine_options[:ssh_options] || {})
#       if server.respond_to?(:private_key) && server.private_key
#         result[:key_data] = [ server.private_key ]
#       elsif server.respond_to?(:key_name) && server.key_name
#         key = get_private_key(server.key_name)
#         if !key
#           raise "Server has key name '#{server.key_name}', but the corresponding private key was not found locally.  Check if the key is in Chef::Config.private_key_paths: #{Chef::Config.private_key_paths.join(', ')}"
#         end
#         result[:key_data] = [ key ]
#       elsif machine_spec.location['key_name']
#         key = get_private_key(machine_spec.location['key_name'])
#         if !key
#           raise "Server was created with key name '#{machine_spec.location['key_name']}', but the corresponding private key was not found locally.  Check if the key is in Chef::Config.private_key_paths: #{Chef::Config.private_key_paths.join(', ')}"
#         end
#         result[:key_data] = [ key ]
#       elsif machine_options[:bootstrap_options][:key_path]
#         result[:key_data] = [ IO.read(machine_options[:bootstrap_options][:key_path]) ]
#       elsif machine_options[:bootstrap_options][:key_name]
#         result[:key_data] = [ get_private_key(machine_options[:bootstrap_options][:key_name]) ]
#       else
#         # TODO make a way to suggest other keys to try ...
#         raise "No key found to connect to #{machine_spec.name} (#{machine_spec.location.inspect})!"
#       end
#       result
#     end

#     def default_ssh_username
#       'root'
#     end

#     def create_ssh_transport(machine_spec, machine_options, server)
#       ssh_options = ssh_options_for(machine_spec, machine_options, server)
#       username = machine_spec.location['ssh_username'] || default_ssh_username
#       if machine_options.has_key?(:ssh_username) && machine_options[:ssh_username] != machine_spec.location['ssh_username']
#         Chef::Log.warn("Server #{machine_spec.name} was created with SSH username #{machine_spec.location['ssh_username']} and machine_options specifies username #{machine_options[:ssh_username]}.  Using #{machine_spec.location['ssh_username']}.  Please edit the node and change the metal.location.ssh_username attribute if you want to change it.")
#       end
#       options = {}
#       if machine_spec.location[:sudo] || (!machine_spec.location.has_key?(:sudo) && username != 'root')
#         options[:prefix] = 'sudo '
#       end

#       remote_host = nil
#       if machine_spec.location['use_private_ip_for_ssh']
#         remote_host = server.private_ip_address
#       elsif !server.public_ip_address
#         Chef::Log.warn("Server #{machine_spec.name} has no public ip address.  Using private ip '#{server.private_ip_address}'.  Set driver option 'use_private_ip_for_ssh' => true if this will always be the case ...")
#         remote_host = server.private_ip_address
#       elsif server.public_ip_address
#         remote_host = server.public_ip_address
#       else
#         raise "Server #{server.id} has no private or public IP address!"
#       end

#       #Enable pty by default
#       options[:ssh_pty_enable] = true
#       options[:ssh_gateway] = machine_spec.location['ssh_gateway'] if machine_spec.location.has_key?('ssh_gateway')

#       ChefMetal::Transport::SSH.new(remote_host, username, ssh_options, options, config)
#     end

#     def self.compute_options_for(provider, id, config)
#       raise "unsupported crowbar provider #{provider}"
#     end

  end
end
