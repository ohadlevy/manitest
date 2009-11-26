#!/usr/bin/ruby
require 'puppet'
require 'getoptlong'
require 'pathname'

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
Usage = "Manitest compiles a manifest using another hosts facts.
  manitest [--debug|-d] [--environment|-e] [--puppetclass|-p]
           [--tmpdir|-t] [--yamlnodefile|-n] [--verbose|-v] [--help|-h]
"
end

option   = {}

opts = GetoptLong.new(
                      [ "--verbose",              "-v", GetoptLong::NO_ARGUMENT ],
                      [ "--debug",                "-d", GetoptLong::NO_ARGUMENT ],
                      [ "--environment",          "-e", GetoptLong::REQUIRED_ARGUMENT ],
                      [ "--devroot",              "-r", GetoptLong::REQUIRED_ARGUMENT ],
                      [ "--tmpdir",               "-t", GetoptLong::REQUIRED_ARGUMENT ],
                      [ "--yamlnodefile",         "-n", GetoptLong::REQUIRED_ARGUMENT ],
                      [ "--help",                 "-h", GetoptLong::NO_ARGUMENT ]
)

# process the parsed options
for opt, arg in opts
  option[(opt.match(/..(.*)/)[1]).to_sym] = arg
end

if option[:help]
  puts Constants::Usage
  exit(0)
end

if option[:yamlnodefile]
  option[:yamlnodefile]  += ".yaml" unless option[:yamlnodefile]=~/yaml$/
else
  warn("must provide a node yaml file")
  puts Constants::Usage
  exit(1)
end

begin
  node = YAML.load_file option[:yamlnodefile]
  raise "Invalid node file - you should use something from /var/lib/puppet/yaml/node directory" unless node.is_a?(Puppet::Node)
end
environment=option[:environment] || node.environment.to_sym
# export all parameters as facter env - overriding our real system values
# this also works for external nodes parameters
node.parameters.each do |k,v|
  begin
    ENV[k]=v
  rescue
    warn "failed to set fact #{k} => #{v}"
  end
end

# Ensure that tmpdir has a trailing slash
option[:tmpdir] += "/" unless option[:tmpdir]=~/\/$/

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
conf = Pathname.new(option[:tmpdir]) + ".tmp_puppet.conf"
nodefile = Pathname.new(option[:tmpdir]) + ".tmp_node.pp"
conf.open(File::CREAT|File::WRONLY|File::TRUNC) {|f| f.write puppet_conf}

nodefile.open(File::CREAT|File::WRONLY|File::TRUNC) do |f|
  f.puts "node '#{node.name}' {"
  f.puts "import '/etc/puppet/manifests/site.pp'"
  node.classes.each do |c|
    f.puts "\tinclude #{c}"
  end
  f.puts "}"
end

cmd = "/usr/bin/puppet --config #{conf} --certname #{node.name} --debug #{nodefile} 2>&1"
puts cmd if option[:debug]
report = []
status = "broken"
IO.popen(cmd) do |puppet|
  while not puppet.eof?
    line = puppet.readline
    report << line
    puts line if option[:debug]
    if line=~/Finishing transaction/ and report[-2]=~/Creating default schedules/
      status = "OK"
      break
    end
  end
end
if option[:verbose]
  puts "The manifest compilation for #{node.name} is #{status}"
end
conf.unlink unless option[:debug]
nodefile.unlink unless option[:debug]
exit(status == "OK" ? 0 : -1)
