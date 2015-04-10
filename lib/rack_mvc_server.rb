require 'rack'
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
    def load_app(ru_file)
      raise ArgumentError, "rackup file (#{ru_file}) not readable" if ! File.readable?(ru_file)
      app, _ = Rack::Builder.parse_file(ru_file)
      Rack::Builder.new do
        use Rack::ContentLength
        run app
      end.to_app
    end
  end
  class Master
    require 'socket'
    require 'yaml'
    require 'net/http'
    require 'rack_mvc_server/const'
    require 'rack_mvc_server/worker'
    require 'mono_logger'
    include Utils
    include Appload

    # Signal     Value     Action   Comment
    # ----------------------------------------------------------------------
    # SIGHUP        1       Term    Hangup detected on controlling terminal or death of controlling process
    # SIGINT        2       Term    Interrupt from keyboard
    # SIGQUIT       3       Core    Quit from keyboard
    # SIGILL        4       Core    Illegal Instruction                            ##cannot trap
    # SIGABRT       6       Core    Abort signal from abort(3)
    # SIGFPE        8       Core    Floating point exception                       ##cannot trap
    # SIGKILL       9       Term    Kill signal
    # SIGSEGV      11       Core    Invalid memory reference                       ##cannot trap
    # SIGPIPE      13       Term    Broken pipe: write to pipe with no readers
    # SIGALRM      14       Term    Timer signal from alarm(2)
    # SIGTERM      15       Term    Termination signal
    # SIGUSR1   30,10,16    Term    User-defined signal 1
    # SIGUSR2   31,12,17    Term    User-defined signal 2
    # SIGCHLD   20,17,18    Ign     Child stopped or terminated
    # SIGCONT   19,18,25    Cont    Continue if stopped
    # SIGSTOP   17,19,23    Stop    Stop process
    # SIGTSTP   18,20,24    Stop    Stop typed at tty
    # SIGTTIN   21,21,26    Stop    tty input for background process
    # SIGTTOU   22,22,27    Stop    tty output for background process
    # SIGWINCH                      "Window" change handler
    # SIGWIND                       Window" change handler


    SIGNALS = [:WINCH, :QUIT, :INT, :TERM, :USR1, :USR2,
               :HUP, :TTIN, :TTOU, :CHLD, :ABRT, :TSTP,
               :PIPE, :ALRM, :CONT ]


    def initialize
      setup_logging
      logger.level = MonoLogger::DEBUG
      logger.debug "initializing ..."
      at_exit { logger.debug "hello from at_exit handler"}
      $PROGRAM_NAME = "mvc server master"
      @workers = {}
      @application = load_app("config.ru")
      BasicSocket.do_not_reverse_lookup = true
      @socket = TCPServer.open(DEFAULT_HOST, DEFAULT_PORT)
      log.info("Listening on #{DEFAULT_HOST}: #{DEFAULT_PORT}, Super Master pid  #{Process.ppid}")
    end
    def start
      @signal_queue = []
      setup_signals
      #create preforking model
      logger.debug("starting work with #{WORKERS} workers")
      loop do
        signal = @signal_queue.shift
        case signal
          when nil
            spawn_workers
            kill_lazy_workers
            remove_dead_workers
            sleep 2
          when :QUIT, :INT
            logger.debug "handling #{signal}"
            kill_each_worker :KILL
            remove_dead_workers
            # When a process terminates(program control flow crosses
            # exit() or return from main) , all of its open files are
            # closed automatically by the kernel. Many programs
            # take advantage of this fact and don't explicitly
            # close open files??
            @socket.close
            break
          when :TTIN, :TTOU
            logger.debug "add fun by increasing or decreasing num of workers"
          when :CHLD
            logger.debug "oh dear worker , wot u die for ?!"
          else
            logger.debug "dummy handle #{signal}"
        end
      end
      logger.debug "bye bye from master"
      exit 0
    end

    def self.start(*args, &block)
      new(*args, &block).start
    end

    private
    # signals are asynchronous, process has to leave everything and run the
    # signal handler first(like wake up if it's in sleep state n run the handler)
    # if the process is running signal handler and another signal comes , than the
    # kernel stacks off to run the handler of the latest signal;
    # The signals SIGKILL and SIGSTOP cannot be trapped, blocked, or ignored.
    def setup_signals
      SIGNALS.each do |signal|
        trap(signal) {
          logger.debug("got signal #{signal}")
          @signal_queue << signal
        }
      end
    end
    def spawn_workers
      worker_number = -1
      until (worker_number += 1) == WORKERS
        @workers.value?(worker_number) && next
        worker = Worker.new(Process.pid, @application, @socket, work_register, worker_number, logger)
        # It's possible to create copies of file descriptors using Socket#dup .
        # other n common way is through Process.fork
        pid = fork { worker.start }
        logger.debug "spawned  worker #{worker_number} with pid #{pid}"
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
        begin
          worker = @workers.delete(pid)
          worker.register.close
          worker.register.unlink
        rescue
          logger.error "prob removing dead  worker"
        end
        logger.debug "cleaned up dead worker #{worker.number} " \
                  "(PID:#{pid}) " \
                  "status: #{status.exitstatus}"
      end
    rescue Errno::ECHILD
      logger.warn "no workers left ?!"
    end
    def kill_worker(signal, pid)
        # _signal_ may be an
        # integer signal number or a POSIX signal name (either with or without
        # a +SIG+ prefix). If _signal_ is negative (or starts
        # with a minus sign),kernel sends the signal to process groups instead of
        # processes.
        Process.kill(signal, pid)
      # ESRCH --> process doesn’t exist.
    rescue Errno::ESRCH
      logger.debug "worker #{pid} not exists, did not receive signal"
      worker = @workers.delete(pid) and worker.close rescue nil
    end
    def kill_each_worker(signal)
      @workers.keys.each { |wpid| kill_worker(signal, wpid) }
    end
    def work_register
      register = Tempfile.new('')
      register.sync = true
      register
    end
    def setup_logging
      $stderr.sync = $stdout.sync = true
      logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{$PROGRAM_NAME} (PID: #{Process.pid})] #{severity} -- #{msg}\n"
      end
    end
    def logger
      @logger || (DAEMONIZE ?  @logger = MonoLogger.new("server.log") : @logger = MonoLogger.new(STDOUT))
    end
  end
  DAEMONIZE ? Process.daemon(fork {Master.start}) : Process.detach(fork{Master.start})
end
