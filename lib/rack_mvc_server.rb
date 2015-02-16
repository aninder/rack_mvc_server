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
      env["PATH_INFO"]=="/favicon.ico/" ||
          env["PATH_INFO"] == "Favicon.icoController"
    end

    def load_app
      #add loading from config.ru
      File.open("config.ru", "r") do |f|
        config = f.readlines

        #require_relative
        reqs = config.find_all { |line| line[/^require_relative /] }
        reqs.each do |req|
          req = "require  '"+Dir.pwd+"/"+req.split[1][1..-2]+"'"
          eval(req)
          # require_relative Dir.pwd+'/config/application'
          # @application = Blog::Application.new.method(:call).to_proc
        end
        #run Blog::Application.new
        run = config.find {|line| line[/^run /]}
        @application = eval(run.split[1]).method(:call).to_proc
      end
    end
  end

  class Master
    require 'socket'
    require 'yaml'
    require 'net/http'
    include Utils

    def initialize
      puts "initializing"
      load_app
    end

    def init
      #create preforking model
      # read, write = UNIXServer.new("/tmp.domain_sock")
      Socket.tcp_server_loop(8080) do |connection|
        request  = connection.recvmsg
        env = setup_env(request)
        # binding.pry
        response = @application.call(env) unless ignore_request?(env)
        connection.puts "HTTP/1.1 #{response[0]}\n"
        response[1].each do |k,v|
          connection.puts "#{k}: #{v} \n"
        end
        response[2].body.each do |body|
          connection.puts("\n#{body}")
        end
        connection.close
      end
    end
  end

  Master.new.init
end
