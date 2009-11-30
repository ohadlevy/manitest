#!/usr/bin/ruby
require 'puppet'
require 'pathname'
require 'optparse'

Puppet[:config] = "/etc/puppet/puppet.conf"
Puppet.parse_config

trap("QUIT"){ exit(-1)}
trap("INT"){ exit(-1)}

module Constants
  Puppet_conf_tmpl = "
[main]
    vardir         = /var/lib/puppet
    logdir         = /var/log/puppet
    rundir         = /var/run/puppet
    ssldir         = $vardir/ssl
    templatedir    = /etc/puppet/templates
    node_terminus  = plain
    statedir       = /var/lib/puppet/state
    noop           = true
[puppet]
    localconfig    = $vardir/localconfig
    factsync       = false
    report         = false
    graph          = false
    pluginsync     = false
"
end

options = {}
optparse = OptionParser.new do |opts|
  # Set a banner, displayed at the top
  # of the help screen.
  opts.define_head "Manitest compiles a manifest using another hosts facts."
  opts.banner = "Usage: #{$0}"
  opts.separator ""

   # Define the options, and what they do
  options[:verbose] = false
  opts.on( '-v', '--verbose', 'Output more information' ) do
    options[:verbose] = true
  end
  options[:debug] = false
  opts.on( '-d', '--debug', 'Output the full puppet debug' ) do
    options[:debug] = true
  end
  opts.on( '-e', '--environment', 'Override node environment' ) do |env|
    options[:environment] = env
  end
  options[:tmpdir] = "/tmp/"
  opts.on( '-t', '--tmpdir DIR', 'Where to write temp files - defaults to /tmp' ) do |tmp|
    options[:tmpdir] = tmp
    # Ensure that tmpdir has a trailing slash
    options[:tmpdir] += "/" unless options[:tmpdir]=~/\/$/
  end
  options[:node] = ""
  opts.on( '-n', '--node FILE', 'YAML node file to use' ) do |file|
    options[:node] = file
  end
  options[:pclasses] = []
  opts.on( '-c', '--class CLASSA,CLASSB', 'node classes to use' ) do |c|
    options[:pclasses] = c.split(",")
  end

  opts.on( '-h', '--help', 'Display this screen' ) do
    puts opts
    exit
  end
end
optparse.parse!

if options[:node].empty?
  warn "Must provide node name, use -h for more info"
  exit 1
end

options[:node] += ".yaml" unless options[:node]=~/yaml$/
unless File.exists? options[:node]
  warn "Unable to find file #{options[:node]}" unless File.exists? options[:node]
  exit 1
end
node = YAML.load_file options[:node]
unless node.is_a?(Puppet::Node)
  warn "Invalid node file - you should use something from /var/lib/puppet/yaml/node directory"
  exit 1
end

klasses = options[:pclasses].size == 0 ? node.classes :  options[:pclasses]

if klasses.size == 0
  warn "Your node file does not contain classes, add some or specify them in the command line"
  exit 1
end

environment=options[:environment] || node.environment.to_sym
puts "Setting up environment: #{environment}" if options[:verbose] or options[:debug]
# export all parameters as facter env - overriding our real system values
# this also works for external nodes parameters
puts "Setting up facts:" if options[:verbose] or options[:debug]
node.parameters.each do |k,v|
  begin
    ENV["facter_#{k}"]=v
    puts "%s=>%s" % [k,v] if options[:verbose] or options[:debug]
  rescue
    warn "failed to set fact #{k} => #{v}"
  end
end


# find env module path
conf = Puppet.settings.instance_variable_get(:@values)
unless conf[environment][:modulepath].nil?
  modulepath =  conf[environment][:modulepath]
else
  Puppet.settings.eachsection do |p|
    path=Puppet.settings.instance_variable_get(:@values)[p][:modulepath]
    modulepath = path and break unless path.nil?
  end
end

# Set the dummy puppet.conf
puppet_conf  = Constants::Puppet_conf_tmpl.dup
puppet_conf << "\tmodulepath   = #{modulepath}\n"

# Write out a puppet.conf and a node.conf.
conf = Pathname.new(options[:tmpdir]) + ".tmp_puppet.conf"
nodefile = Pathname.new(options[:tmpdir]) + ".tmp_node.pp"
conf.open(File::CREAT|File::WRONLY|File::TRUNC) {|f| f.write puppet_conf}
nodefile.open(File::CREAT|File::WRONLY|File::TRUNC) do |f|
  f.puts "node '#{node.name}' {"
  f.puts "import '/etc/puppet/manifests/site.pp'"
  klasses.each do |c|
    f.puts "\tinclude #{c}"
  end
  f.puts "}"
end

cmd = "/usr/bin/puppet --config #{conf} --certname #{node.name} --debug #{nodefile} 2>&1"
puts cmd if options[:debug]
report = []
status = "broken"
IO.popen(cmd) do |puppet|
  while not puppet.eof?
    line = puppet.readline
    report << line
    puts line if options[:debug]
    if line=~/Finishing transaction/ and report[-2]=~/Creating default schedules/
      status = "OK"
      break
    end
  end
end
if options[:verbose] or  options[:debug]
  puts "The manifest compilation for #{node.name} is #{status}"
end
conf.unlink unless options[:debug]
nodefile.unlink unless options[:debug]
exit(status == "OK" ? 0 : -1)
