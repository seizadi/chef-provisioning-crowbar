# OpenCrowbar for Chef-Provisioning

**Chef Provisioning with Crowbar to treat your metal like a cloud**

This repo contains the interface between Chef Provisioning (https://github.com/opscode/chef-provisioning/) and OpenCrowbar.

> make sure you are running Ruby 1.9 and related gems for this tool.  check `ruby -v` to verify.

> Better yet: *use chef-dk* - it now has chef-provisioning gems included.

## Background

Crowbar discovers and manages your gear - preferably hardware nodes.  The typical model would be to get Crowbar running on your admin network, and start booting up your gear.  Crowbar will discover and inventory your gear automatically.  You can then use Chef Provisioning to tell Crowbar to do all those things it's good at: install the OS you want, configure the BIOS, RAID, networking, and manage the power states of the gear.  You can keep using Chef-Provisioning and Crowbar when you want to power down or re-image those nodes.

Crowbar manages nodes in groups of "deployments." All nodes start and spend their lives in the foundational "system" deployment. They're then added to deployments you create to effect change on them.  By creating a new deployment and adding nodes to it, all the roles you defined as belonging to that deployment get run on the gear.   

When you write a recipe with Chef Provisioning and Crowbar, Chef Provisioning requests from Crowbar to "allocate_machine."  Crowbar then looks in its inventory for a node that is "alive" according to Crowbar (Crowbar can power it on and ssh into it,) but not used in any other deployments than "system."  Once Crowbar finds an appropriate node, it adds the node to the "ready" deployment (default name, and will create it if necessary.) This will start Crowbar configuring the hardware, OS, network, etc.  Chef Provisioning waits patiently for all this to get finished, so it can consider the node "ready."

A Chef Provisioning "ready" machine is a Crowbar node which has completed the tasks in the proper deployment ("ready"), and Crowbar has given up managing it until further notice.  In Crowbar terms, that means that the milestone noderole for the deployment is 'active', and the node is marked in Crowbar as node["available"]:false so the annealer will not manage the node's noderoles.  

## Example

Chef Provisioning with Crowbar will treat your gear like a cloud! 

Example Session:

See the nodes available from Crowbar:

```bash
bash-4.1# crowbar deployments nodes "system" | grep '"alias"'
    "alias": "d52-54-32-f9-00-00",
    "alias": "d52-54-32-f8-00-00",
    "alias": "d52-54-32-f5-00-00",
    "alias": "d52-54-32-f6-00-00",
    "alias": "d52-54-32-f7-00-00",
    "alias": "be727e682d0d",
bash-4.1# 
```

And you can see them with `knife` against the chef server in Crowbar:

```bash
$ knife node list -s http://192.168.124.10
be727e682d0d.crowbar.org
d52-54-32-f5-00-00.crowbar.org
d52-54-32-f6-00-00.crowbar.org
d52-54-32-f7-00-00.crowbar.org
d52-54-32-f8-00-00.crowbar.org
d52-54-32-f9-00-00.crowbar.org
```

So, to provision one of these, run the example recipe:

Example Recipe:

```ruby
require 'chef/provisioning'
with_driver 'crowbar'

# Here I indicate the chef server running inside Crowbar.  If you like, use your own Chef Server, or just
# use Chef Zero by calling chef-client -z <recipe_name>.

with_chef_server 'https://192.168.124.10',
                 :client_name => 'metal',
                 :signing_key_filename => '/home/metal/.chef/metal.pem'

machine "chef-provisioning-#{rand(1000)}" do
  machine_options :crowbar_options => { 'provisioner-target_os' => 'centos-7.0' }
end
```

Example chef-client Invocation:

```bash
$ chef-client ./crowbar_test.rb 
```

and you will see the new node being allocated and made ready.  Here's a few nodes in the "ready"
deployment.

```bash
# crowbar deployments nodes "ready" | grep '"alias"'
    "alias": "chef-provisioning-another-brother-42",
    "alias": "chef-provisioning-another-brother-97",
    "alias": "chef-provisioning-example-56",
    "alias": "chef-provisioning-another-brother-80",
```


Real world use would have you put a run-list in the `machine` resource, so chef can use the nodes to actually do things.

## Setup

### Networking

Before you start, your chef-provisioning box must be on the crowbar administration network, so it can ssh into the slave nodes and do its cheffy thing.  In our typical development environments, that's simply a matter of setting your host OSs network as follows:

```bash
$ sudo ip a add 192.168.124.2/24 dev docker0
```

### Chef

#### Chef-DK

I use the chef-dk, which now has Chef Provisioning built in.  Get your `knife` and `chef-client` all setup for development work.

#### Gems, no Chef-DK

Or you can use Chef gems.

*Gem dependencies* You also need the HTTParty, Chef and Chef-Metal gems: `sudo gem install httparty chef chef-metal`

## Example gem build script and test run

This is an example file to run and build chef provisioning crowbar.

All the exciting stuff is happening in chef-provisioning-crowbar/cookbooks/app/recipes/crowbar-test.rb

/$HOME/build_and_test_chef-provisioning-crowbar.sh

```bash
# source the chef-dk env
. $HOME/.bash_profile
CPC_REPO_PATH=<path to chef-provisioning-crowbar git repo>
cd ${CPC_REPO_PATH}
gem build chef-provisioning-crowbar.gemspec 
gem install --ignore-dependencies --no-ri --no-rdoc chef-provisioning-crowbar-0.0.2.gem
cd ${CPC_REPO_PATH}/cookbooks/app/recipes/
# run with debugging..
#chef-client -l debug -z crowbar_test.rb
# or not
#chef-client -z crowbar_test.rb
# or omit -z to use a chef server indicated elsewhere
chef-client ./crowbar_test.rb
```
