require "./requires"
require "./procodile/app_determination"
require "./procodile/cli"

module Procodile
  class Error < Exception
  end

  private def self.root : String
    File.expand_path("..", __DIR__)
  end

  private def self.bin_path : String
    File.join(root, "bin", "procodile")
  end
end

ORIGINAL_ARGV = ARGV.join(" ")
command = ARGV[0]? || "help"
options = {} of Symbol => String
cli = Procodile::CLI.new

OptionParser.parse do |parser|
  parser.banner = "Usage: procodile #{command} [options]"

  parser.on("-r", "--root PATH", "The path to the root of your application") do |root|
    options[:root] = root
  end

  parser.on("--procfile PATH", "The path to the Procfile (defaults to: Procfile)") do |path|
    options[:procfile] = path
  end

  parser.invalid_option do |flag|
    STDERR.puts "Invalid option: #{flag}.\n\n"
    STDERR.puts parser
    exit 1
  end

  parser.missing_option do |flag|
    STDERR.puts "Missing option for #{flag}\n\n"
    STDERR.puts parser
    exit 1
  end

  if cli.class.commands[command]? && (option_block = cli.class.commands[command].options)
    option_block.call(parser, cli)
  end
end

# Get the global configuration file data
global_config_path = ENV["PROCODILE_CONFIG"]? || "/etc/procodile"

global_config = if File.file?(global_config_path)
                  Array(Procodile::Config::GlobalOption).from_yaml(File.read(global_config_path))
                else
                  [] of Procodile::Config::GlobalOption
                end

# Create a determination to work out where we want to load our app from
ap = Procodile::AppDetermination.new(
  FileUtils.pwd,
  options[:root]?,
  options[:procfile]?,
  global_config
)

if ap.ambiguous?
  if (app_id = ENV["PROCODILE_APP_ID"]?)
    ap.set_app_id_and_find_root_and_procfile(app_id.to_i)
  elsif ap.app_options.empty?
    STDERR.puts "Error: Could not find Procfile in #{FileUtils.pwd}/Procfile".colorize.red
    exit 1
  else
    puts "There are multiple applications configured in #{global_config_path}"
    puts "Choose an application:".colorize.light_gray.on_magenta

    ap.app_options.each do |i, app|
      col = i % 3
      print "#{(i + 1)}) #{app}"[0, 28].ljust(col != 2 ? 30 : 0, ' ')
      if col == 2 || i == ap.app_options.size - 1
        puts
      end
    end

    input = STDIN.gets
    if !input.nil?
      app_id = input.strip.to_i - 1

      if ap.app_options[app_id]?
        ap.set_app_id_and_find_root_and_procfile(app_id)
      else
        puts "Invalid app number: #{app_id + 1}"
        exit 1
      end
    end
  end
end

begin
  if command != "help"
    cli.config = Procodile::Config.new(ap.root || "", ap.procfile)

    if cli.config.user && ENV["USER"] != cli.config.user
      STDERR.puts "Procodile must be run as #{cli.config.user}. Re-executing as #{cli.config.user}...".colorize.red

      Process.exec(
        command: "sudo -H -u #{cli.config.user} -- #{$0} #{ORIGINAL_ARGV}",
        shell: true
      )
    end
  end

  cli.dispatch(command)
rescue ex : Procodile::Error
  STDERR.puts "Error: #{ex.message}".colorize.red
  exit 1
end
