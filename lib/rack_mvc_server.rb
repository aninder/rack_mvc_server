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
  class Master
    require 'socket'
    require 'yaml'
    require 'net/http'
    #add loading from config.ru
    require_relative Dir.pwd+'/config/application'
    @application = Blog::Application.new.method(:call).to_proc
    env={}

    #create preforking model
    # read, write = UNIXServer.new("/tmp.domain_sock")
      Socket.tcp_server_loop(8080) do |connection|
        request  = connection.recvmsg
        get = request[0].split("\n").first
        get.match("GET ([^ ]+).*$")
        env['PATH_INFO']=$1
        response = @application.call(env) unless env["PATH_INFO"]=="/favicon.ico/"
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
