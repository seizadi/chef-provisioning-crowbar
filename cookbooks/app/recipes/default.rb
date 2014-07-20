require 'chef_metal_crowbar'
 
random = rand(10 ** 4)
  
with_chef_server 'https://127.0.0.1:443',
                 :client_name => 'crowbar',
                 :signing_key_filename => '/root/.chef/crowbar.pem'
 
with_provisioner_options(
  'bootstrap_options' => {
    os: 'ubuntu-12.04'
  }
)
 
num_servers = 1
 
# build a sample server
1.upto(num_servers) do |i|
  machine "hostname-#{random}" do
    chef_environment 'test'
  end 
end