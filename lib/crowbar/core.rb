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
require 'net/http'
require 'net/http/digest_auth'
require 'uri'
require 'json'
require 'getoptlong'

module Crowbar

  class Core

    API_BASE              = "/api/v2/"

    def initialize(url = "http://127.0.0.1:3000", username = "crowbar", password = "crowbar")
        debug "initializing #{@url}"
        @url = url
        @username = username
        @password = password
        debug "initialize #{@url}"
    end

    def get(path)
      go(Net::HTTP::Get,path)
    end

    def post(path, data=nil)
      go(Net::HTTP::Post,path,data)
    end

    def put(path, data=nil)
      go(Net::HTTP::Put,path,data)
    end

    def delete(path)
      go(Net::HTTP::Delete,path)
    end

    private

    # connect to the Crowbar API
    # this currently AUTHS every call, we need to optimize that so that we can reuse the auth tokens
    def authenticate

      # build request
      request_headers={
        "Accept" => "application/json",
        "Content-Type" => "application/json"}
      #request_headers['x-return-attributes']=$attributes if $attributes
      # build URL
      uri = URI.parse(@url)
      uri.user= @username
      uri.password= @password
      # starting HTTP session
      res=nil
      Net::HTTP.start(uri.host, uri.port) {|http|
        http.read_timeout = $timeout
        r = req.new(uri.request_uri,request_headers)
        r.body = data if data
        res = http.request r
        debug "(a) return code: #{res.code}"
        debug "(a) return body: #{res.body}"
        debug "(a) return headers:"
        res.each_header do |h, v|
          debug "#{h}: #{v}"
        end

        if res['www-authenticate']
          debug "(a) uri: #{uri}"
          debug "(a) www-authenticate: #{res['www-authenticate']}"
          debug "(a) req-method: #{req::METHOD}"
          auth=Net::HTTP::DigestAuth.new.auth_header(uri,
                                                     res['www-authenticate'],
                                                     req::METHOD)
          r.add_field 'Authorization', auth
          res = http.request r
        end
      }
      res
    end

     # Common data and debug handling.
    def self.go(verb,path,data=nil)
      uri = URI.parse(@url + API_BASE + path)
      # We want to give valid JSON to the API, so if we were
      # handed an array or a hash as the data to be messed with,
      # turn it into a blob of JSON.
      data = data.to_json if data.is_a?(Array) || data.is_a?(Hash)
      res = authenticate(verb,uri,data)
      debug "(#{verb}) hostname: #{uri.host}:#{uri.port}"
      debug "(#{verb}) request: #{uri.path}"
      debug "(#{verb}) data: #{data}"
      debug "(#{verb}) return code: #{res.code}"
      debug "(#{verb}) return body: #{res.body}"
      [ JSON.parse(res.body), res.code.to_i ]
    end

    def exists?(type, name)
      get("#{type}s/#{name}").code == 200
    end


    # debug messages
    def debug(msg)
      puts msg
    end

  end

end