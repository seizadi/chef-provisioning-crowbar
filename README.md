# OpenCrowbar for Chef-Provisioning

This repo contains the interface between Chef Provisioning (https://github.com/opscode/chef-provisioning/) and OpenCrowbar.

> make sure you are running Ruby 1.9 and related gems for this tool.  check `ruby -v` to verify.

## Background
A chef-provisioning "allocated-state" machine is a Crowbar "alive" machine (part of the Annealer graph) that is has been moved from the 'system' deployment to another deployment - by default, it's called the "ready" deployment.

A chef-provisioning "ready" machine is a Crowbar node in the proper deployment ("ready"), the milestone noderole is 'active', and the node is marked in Crowbar as node["available"]:false so the annealer will not manage the node's noderoles.

## Important
Before you start, your chef-provisioning box must be on the crowbar administration network, so it can ssh into the slave nodes and do its cheffy thing.  In our typical development environments, that's simply a matter of setting your host OSs network as follows:

You also need the HTTParty, Chef and Chef-Metal gems: `sudo gem install httparty chef chef-metal`

```bash
$ sudo ip a add 192.168.124.2/24 dev docker0
```

### Example gem build script and test run

This is an example file to run and build chef provisioning crowbar.

All the exciting stuff is happening in chef-provisioning-crowbar/cookbooks/app/recipes/, but event that's not a lot of exciting.


 /$HOME/build_and_test_chef-provisioning-crowbar.sh

```bash
CMCROWBAR_REPO=/VMs/repos/chef-provisioning-crowbar/
cd ${CMCROWBAR_REPO}
sudo gem build chef-provisioning-crowbar.gemspec 
sudo gem install --ignore-dependencies --no-ri --no-rdoc chef-provisioning-crowbar-0.0.1.gem
cd ${CMCROWBAR_REPO}/cookbooks/app/recipes/
#chef-client -l debug -z crowbar_test.rb
chef-client -z crowbar_test.rb
```
