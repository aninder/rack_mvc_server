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
    require 'rack_mvc_server/worker'
    include Utils
    include Appload
    include RackMvcServer::Const

    def initialize
      logger.info "initializing ..."
      @workers = {}
      @master_pid = Process.pid
      $PROGRAM_NAME = "mvc server master"
      $stderr.sync = $stdout.sync = true
      setup_logging
      load_app("config.ru")
      @socket = TCPServer.open(DEFAULT_HOST, DEFAULT_PORT)
      logger.info("Listening on #{DEFAULT_HOST}: #{DEFAULT_PORT}")
    end
    def start
        #create preforking model
      logger.info("Spawning #{WORKERS} workers")
      loop do
        spawn_workers
        kill_lazy_workers
        remove_dead_workers
      end
    end

    private
    def spawn_workers
      worker_number = -1
      until (worker_number += 1) == WORKERS
        @workers.value?(worker_number) && next
        worker = Worker.new(@master_pid, @application, @socket, work_register, worker_number, logger)
        pid = fork { worker.start }
        logger.info "spawned  worker #{worker_number} with pid #{pid}"
        @workers[pid] = worker
      end
    end
    def kill_lazy_workers
      now = Time.now
      @workers.each_pair do |pid, worker|
        unless (now - worker.register.ctime) <= WORKER_MAX_TIME_ON_CLIENT_REQUEST
          logger.error "worker #{worker.number} (PID:#{pid}) "\
                       "took too long to serve client request"
          kill_worker('HUP', pid)
        end
      end
    end
    def remove_dead_workers
      loop do
        # wait non block
        pid, status = Process.wait2(-1, Process::WNOHANG) || break
        reap_worker(pid, status)
      end
    rescue Errno::ECHILD
      logger.warn "no workers left to reap !"
    end
    def reap_worker(pid, status)
      worker = @workers.delete(pid)
      begin
        worker.register.close
        worker.registe.unlink
      rescue
        logger.warn "prob while cleaning tempfile"
      end
      logger.info "reaped worker #{worker.number} " \
                  "(PID:#{pid}) " \
                  "status: #{status.exitstatus}"
    end
    def kill_worker(signal, pid)
      Process.kill(signal, pid)
      # ESRCH --> process doesn’t exist.
    rescue Errno::ESRCH
    end
    def work_register
      register = Tempfile.new('')
      register.sync = true
      register
    end
    def setup_logging
      logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{$PROGRAM_NAME} (PID: #{Process.pid})] #{severity} -- #{msg}\n"
      end
    end
    def logger
      DAEMONIZE ?  @logger ||= Logger.new("server.log") : @logger ||= Logger.new(STDOUT)
    end
  end
  Master.new.start
end
