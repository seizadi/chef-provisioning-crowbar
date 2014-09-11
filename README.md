# OpenCrowbar for Chef-Metal

This repo contains the interface between Chef Metal (https://github.com/opscode/chef-metal/) and OpenCrowbar.

gem build crowbar.gemspec
sudo gem install -f -V --ignore-dependencies ./chef-metal-crowbar-0.0.1.gem 

A chef-metal "allocated" state machine is a Crowbar "alive" machine (part of the Annealer graph) that is being moved from the System deployment to another deployment - by default, the "ready" deployment.

A chef-metal "ready" machine is a Crowbar node in the proper deployment ("ready"), the milestone noderole is 'active', and the node is marked in Crowbar as node["available"]:false so the annealer will not manage the node's noderoles.

