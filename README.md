# OpenCrowbar for Chef-Metal

This repo contains the interface between Chef Metal (https://github.com/opscode/chef-metal/) and OpenCrowbar.

gem build crowbar.gemspec
sudo gem install -f -V --ignore-dependencies ./chef-metal-crowbar-0.0.1.gem 

## Background
A chef-metal "allocated-state" machine is a Crowbar "alive" machine (part of the Annealer graph) that is has been moved from the 'system' deployment to another deployment - by default, it's called the "ready" deployment.

A chef-metal "ready" machine is a Crowbar node in the proper deployment ("ready"), the milestone noderole is 'active', and the node is marked in Crowbar as node["available"]:false so the annealer will not manage the node's noderoles.

## Important
Before you start, your chef-metal box must be on the crowbar administration network, so it can ssh into the slave nodes and do its cheffy thing.  In our typical development environments, that's simply a matter of setting your host OSs network as follows:

```bash
$ sudo ip a add 192.168.124.2/24 dev docker0
```
