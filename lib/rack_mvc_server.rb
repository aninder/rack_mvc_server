# require "rack_mvc_server/version"
=begin
load the app
  read config.ru
  class eval the load the paths
  read the Gemfile , require all the gems
  find run command and load the objext and send the call message to it
make a listener socket
prefork worker threads
forward tje connection to the app by calling it's call method
forward the reaponse to the xlient
=end
# $LOAD_PATH << temp
# File.open("#{temp}/config.ru","r") do |f|
#   lines = f.readlines
#   lines.grep(/^require/).each do |req|
#    require req.gsub(/(.*)\"(.+)\"/,temp+'\2.rb')
#    #    eval req
#   end
#   puts lines.grep(/\s*run/)[0].gsub("run\s","")
# end
module RackMvcServer

  module Utils
    def setup_env(request)
      env = Hash.new
      get = request[0].split("\n").first
      get.match("GET ([^ ]+).*$")
      env['PATH_INFO']=$1
      env
    end
    def ignore_request?(env)
      env["PATH_INFO"]=~ /^\/favicon.ico/ ||
          env["PATH_INFO"] =~ /^\/Favicon.icoController/
    end
  end

  module Appload
    def load_app
      #add loading from config.ru
      File.open("config.ru", "r") do |f|
        instance_eval  f.read, f.path
      end
    end
    def map(path)
      puts ".....map NOT IMPLEMENTED YET..."
    end
    def run(obj)
      @application = obj.method(:call).to_proc
    end
    def require_relative(str)
      req = "require '"+Dir.pwd+"/"+str+"'"
      eval(req)
    end
  end

  class Master
    require 'socket'
    require 'yaml'
    require 'net/http'
    include Utils
    include Appload

    def initialize
      puts "initializing ..."
      load_app
      puts "app loaded ...."
    end
    def init
      #create preforking model
      # read, write = UNIXServer.new("/tmp.domain_sock")
      Socket.tcp_server_loop(8080) do |connection|
        # binding.pry
        # fork do
          request = connection.recvmsg
          env = setup_env(request)
          if ignore_request?(env)
            send_response_to_client(connection, [200, {}, []])
          else
            response = @application.call(env)
            send_response_to_client(connection, response)
          end
          connection.close
        # end
      end
    end

    private
    def send_response_to_client(connection, response)
      if response.kind_of?Array
        connection.puts "HTTP/1.1 #{response[0]}\n"
        response[1].each do |k,v|
          connection.puts "#{k}: #{v} \n"
        end
        response[2].each do |body|
          connection.puts("\n#{body}")
        end
      else
        connection.puts "HTTP/1.1 #{response.status}\n"
        response.headers.each do |k,v|
          connection.puts "#{k}: #{v} \n"
        end
        response.body.each do |body|
          connection.puts("\n#{body}")
        end
      end
    end
  end
  Master.new.init

end
