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
    def setup_env(sock_message)
      env = Hash.new
      get = sock_message[0].split("\n").first
      get.match("GET ([^ ]+).*$")
      env['PATH_INFO']=$1
      return env
    end
  end

  module Appload

    def load_app(config)
      raise ArgumentError, "rackup file (#{config}) not readable" if ! File.readable?(config)
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
    require 'rack_mvc_server/const'
    include Utils
    include Appload
    include RackMvcServer::Const
    
    def initialize
      $stderr.sync = $stdout.sync = true
      setup_logging
      logger.info "initializing ..."
      load_app("config.ru")
      logger.info "app loaded ...."
    end
    def init
      #create preforking model
      # read, write = UNIXServer.new("/tmp.domain_sock")
      Socket.tcp_server_loop(DEFAULT_PORT) do |socket|
        begin
          # binding.pry
          # fork do
            env = setup_env(socket.recvmsg)
              response = @application.call(env)
              send_response_to_client(socket, response)
        ensure
          socket.close
        end
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

    def setup_logging
      logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{$PROGRAM_NAME} (PID: #{Process.pid})] #{severity} -- #{msg}\n"
      end
    end

    def logger
      if DAEMONIZE
        @logger ||= Logger.new("server.log")
      else
        @logger ||= Logger.new(STDOUT)
      end
    end

  end
  Master.new.init

end
