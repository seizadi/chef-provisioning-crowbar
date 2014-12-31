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

require 'rubygems'
require 'httparty'
require 'json'


class Crowbar
  include HTTParty

  API_BASE = '/api/v2'



  def initialize(url = "http://127.0.0.1:3000", u = "crowbar", p = "crowbar")
      @url = url + API_BASE
      self.class.digest_auth u, p
      self.class.base_uri @url
      debug "initialize #{@url}"
  end

  @llevel = :info
  def log_level(level)
    @llevel = level
    debug("incoming #{level} instance #{@llevel}")
  end

  def debug(msg)
    puts "\nCROWBAR #{@llevel}: #{msg}" if @llevel == :debug
  end

#  debug_output $stderr
  format :json

  #http://192.168.222.6:3000/api/v2/nodes/1/attribs/provisioner-access_keys
  def add_sshkey(sshkey)
    res = self.class.get("/nodes/1/attribs/provisioner-access_keys")
    if res.code != 200
      raise("Could not get sshkey on admin node #{res.code} #{res.message}")
    end
    debug res
    res = self.class.put("/nodes/1/attribs/provisioner-access_keys", :body => sshkey)
    if res.code != 200
      raise("Could not put sshkey on admin node #{res.code} #{res.message}")
    end
    return res
  end

  def deployment_create(name, parent_id=1)
    data = { :name => name, :parent_id => parent_id }
    res = self.class.post("/deployments", :body => data)
    if res.code != 200
      raise("Could not create deployment #{name}. #{res.code} #{res.message}")
    end
    res
  end

  def commit_deployment(name)
    deployment_set(name,"commit")
  end

  def propose_deployment(name)
    deployment_set(name,"propose")
  end

  def deployment_set(name,state)
    res = self.class.put("/deployments/#{name}/#{state}")
    if res.code != 200
      raise("Could not set deployment #{name} to #{state}. #{res.code} #{res.message}")
    end
    return res
  end

  def deployment_exists?(name)
    res = self.class.get("/deployments/#{name}")
    debug("res code deployment exists #{res.code}")
    return false unless res.code == 200
    true
  end

  def node_exists?(name)
    res = self.class.get("/nodes/#{name}")
    debug("res code node exists #{res.code}")
    return false unless res.code == 200
    true
  end

  def non_admin_nodes_in_deployment(name, attrs={})
    #attrs = {'x-return-attributes' => '["admin"]' } 
    n = nodes_in_deployment(name,attrs)
    n.reject{ |e| e["admin"] == true } || []
  end


  def find_node_in_deployment(node,deployment,attrs=[])
    res = self.class.get("/deployments/#{deployment}/nodes", :headers => {'x-return-attributes' => "#{attrs.to_json}" } )
    res.index{|e|e["name"] == node || e["id"] == node} 
  end

  def nodes_in_deployment(name,attrs={})
    self.class.get("/deployments/#{name}/nodes", :headers => attrs )
  end

  def set_deployment_to_proposed(name)
    self.class.put("/deployments/#{name}/propose")
  end

  def ssh_private_key(name)
    res = self.class.get("nodes/#{name}/attribs/#{attrib}")
    if res.code != 200
      raise("Could not get node \"#{name}\" ssh keys")
    end
    res
  end

  def node_status(id)
    res = self.class.get("http://127.0.0.1:3000/api/status/nodes/#{id}" )
    if res.code != 200
      raise("Could not get node status #{res.code} #{res.message}")
    end
    res
  end

  def node_alive?(node_id)
    n = node(node_id, ['alive'])
    n["alive"]
  end 

  def node_ready(node_id,node_role_id)
    # get noderole state == 0 and runcount >= 1
    # get node alive = true
    nr = self.class.get("/node_roles/#{node_role_id}")
    if nr["state"] == 0 && nr["run_count"] >= 1 && node_alive?(node_id)
      return true
    else
      return false
    end
  end

  def set_node(id, data)
    res = self.class.put("/nodes/#{id}", :body => data)
    if res.code != 200
      raise("Could not update node #{res.code} #{res.message}")
    end
    return res
  end

  def node(id,attrs=[])
    my_head = {}
    attrs.size > 0 && my_head = { :headers => {'x-return-attributes' => attrs.to_json }  }
    res = self.class.get("/nodes/#{id}", my_head )
    if res.code != 200
      raise("Could not get node \"#{id}\" #{res.code} #{res.message}")
    end
    res
  end

  def node_attrib(id,attrib)
    res = self.class.get("/nodes/#{id}/attribs/#{attrib}")
    if res.code != 200
      raise("Could not get node \"#{id}\" attrib #{attrib} - #{res.code} #{res.message}")
    end
    return res
  end

  def deployment(id,attrs={})
    res = self.class.get("/deployments/#{id}", :headers => attrs )
    if res.code != 200
      raise("Could not get deployment \"#{id}\" #{res.code} #{res.message}")
    end
    return res
  end

  def power(name,action)
    res = self.class.put("/nodes/#{name}/power?poweraction=#{action}")
    if res.code != 200
      raise("Could not power #{action} node #{name}")
    end
  end

  def set_node_role_attrib(nr_id, attrib, value)
    res = self.class.put("/node_roles/#{nr_id}/attribs/#{attrib}", :body => { :value => "#{value}" } )
    if res.code != 200
      raise("Could not set node_role #{nr_id} attrib #{attrib} to value #{value}")
    end
    res
  end

  def set_node_attrib(n_id, attrib, value)
    res = self.class.put("/nodes/#{n_id}/attribs/#{attrib}", :body => { :value => "#{value}" } )
    if res.code != 200
      raise("Could not set node #{n_id} attrib #{attrib} to value #{value}: code #{res.code} #{res.message}")
    end
    res
  end

  def bind_node_role(data)
    raise("Count not bind role to node. #{data}") unless
      res = self.class.post("/node_roles", :body => data)
    res['id']
  end


  private


#  # connect to the Crowbar API
#  # this currently AUTHS every call, we need to optimize that so that we can reuse the auth tokens
#  def authenticate(req,uri,data=nil)
#    
#      # build request
#      request_headers={
#        "Accept" => "application/json",
#        "Content-Type" => "application/json"}
#      #request_headers['x-return-attributes']=$attributes if $attributes
#      # build URL
#      uri = URI.parse(@url)
#      uri.user= @username
#      uri.password= @password
#      # starting HTTP session
#      res=nil
#      Net::HTTP.start(uri.host, uri.port) {|http|
#        http.read_timeout = 500
#        r = http.new(uri.request_uri,request_headers)
#        r.body = data if data
#        res = http.request r
#        debug "(a) return code: #{res.code}"
#        debug "(a) return body: #{res.body}"
#        debug "(a) return headers:"
#        res.each_header do |h, v|
#          debug "#{h}: #{v}"
#        end
#
#        if res['www-authenticate']
#          debug "(a) uri: #{uri}"
#          debug "(a) www-authenticate: #{res['www-authenticate']}"
#          debug "(a) req-method: #{req::METHOD}"
#          auth=Net::HTTP::DigestAuth.new.auth_header(uri,
#                                                     res['www-authenticate'],
#                                                     req::METHOD)
#          r.add_field 'Authorization', auth
#          res = http.request r
#        end
#      }
#    res
#  end
#
#   # Common data and debug handling.
#  def go(verb,path,data=nil)
#    uri = URI.parse(@url + API_BASE + path)
#    # We want to give valid JSON to the API, so if we were
#    # handed an array or a hash as the data to be messed with,
#    # turn it into a blob of JSON.
#    data = data.to_json if data.is_a?(Array) || data.is_a?(Hash)
#    res = authenticate(verb,uri,data)
#    debug "(#{verb}) hostname: #{uri.host}:#{uri.port}"
#    debug "(#{verb}) request: #{uri.path}"
#    debug "(#{verb}) data: #{data}"
#    debug "(#{verb}) return code: #{res.code}"
#    debug "(#{verb}) return body: #{res.body}"
#    [ JSON.parse(res.body), res.code.to_i ]
#  end
#
#


end

