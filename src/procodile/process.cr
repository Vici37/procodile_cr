require "procodile/instance"

module Procodile
  class Process
    MUTEX = Mutex.new

    attr_reader :config, :name
    attr_accessor :command, :options, :log_color, :removed

    def initialize(config, name, command, options={})
      @config = config
      @name = name
      @command = command
      @options = options
      @log_color = 0
      @instance_index = 0
    end

    #
    # Increase the instance index and return
    #
    def get_instance_id
      MUTEX.synchronize do
        @instance_index = 0 if @instance_index == 10000
        @instance_index += 1
      end
    end

    #
    # Return all environment variables for this process
    #
    def environment_variables
      global_variables = @config.environment_variables
      process_vars = @config.process_options[@name] ? @config.process_options[@name]["env"] || {} : {}
      process_local_vars = @config.local_process_options[@name] ? @config.local_process_options[@name]["env"] || {} : {}
      global_variables.merge(process_vars.merge(process_local_vars)).each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = value.to_s
      end
    end

    #
    # How many instances of this process should be started
    #
    def quantity
      @options["quantity"] || 1
    end

    #
    # The maximum number of times this process can be respawned in the given period
    #
    def max_respawns
      @options["max_respawns"] ? @options["max_respawns"].to_i : 5
    end

    #
    # The respawn window. One hour by default.
    #
    def respawn_window
      @options["respawn_window"] ? @options["respawn_window"].to_i : 3600
    end

    #
    # Return the path where log output for this process should be written to. If
    # none, output will be written to the supervisor log.
    #
    def log_path
      @options["log_path"] ? File.expand_path(@options["log_path"], @config.root) : default_log_path
    end

    #
    # Return the defualt log file name
    #
    def default_log_file_name
      @options["log_file_name"] || "#{@name}.log"
    end

    #
    # Return the log path for this process if no log path is provided and split logs
    # is enabled
    #
    def default_log_path
      if @config.log_root
        File.join(@config.log_root, default_log_file_name)
      end
    end

    #
    # Return the signal to send to terminate the process
    #
    def term_signal
      @options["term_signal"] || "TERM"
    end

    #
    # Defines how this process should be restarted
    #
    # start-term = start new instances and send term to children
    # usr1 = just send a usr1 signal to the current instance
    # usr2 = just send a usr2 signal to the current instance
    # term-start = stop the old instances, when no longer running, start a new one
    #
    def restart_mode
      @options["restart_mode"] || "term-start"
    end

    #
    # Return the first port that ports should be allocated from for this process
    #
    def allocate_port_from
      @options["allocate_port_from"]
    end

    #
    # Is this process enabled for proxying?
    #
    def proxy?
      @options.key?("proxy_port")
    end

    #
    # Return the port for the proxy to listen on for this process type
    #
    def proxy_port
      proxy? ? @options["proxy_port"].to_i : nil
    end

    #
    # Return the port for the proxy to listen on for this process type
    #
    def proxy_address
      proxy? ? @options["proxy_address"] || "127.0.0.1" : nil
    end

    #
    # Return the network protocol for this process
    #
    def network_protocol
      @options["network_protocol"] || "tcp"
    end

    #
    # Generate an array of new instances for this process (based on its quantity)
    #
    def generate_instances(supervisor, quantity=self.quantity)
      Array.new(quantity) { |i| create_instance(supervisor) }
    end

    #
    # Create a new instance
    #
    def create_instance(supervisor)
      Instance.new(supervisor, self, get_instance_id)
    end

    #
    # Return a hash
    #
    def to_hash
      {
        :name => self.name,
        :log_color => self.log_color,
        :quantity => self.quantity,
        :max_respawns => self.max_respawns,
        :respawn_window => self.respawn_window,
        :command => self.command,
        :restart_mode => self.restart_mode,
        :log_path => self.log_path,
        :removed => self.removed ? true : false,
        :proxy_port => proxy_port,
        :proxy_address => proxy_address
      }
    end

    #
    # Is the given quantity suitable for this process?
    #
    def correct_quantity?(quantity)
      if self.restart_mode == "start-term"
        quantity >= self.quantity
      else
        self.quantity == quantity
      end
    end
  end
end
