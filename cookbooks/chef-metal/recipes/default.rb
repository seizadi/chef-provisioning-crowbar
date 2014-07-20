%w{chef-metal chef-metal-crowbar}.each do |pkg|
  chef_gem "#{pkg}" do
    action :install
  end
end
 
require 'chef_metal'
require 'cheffish'