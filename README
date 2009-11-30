h1. Manitest compiles a manifest using another hosts facts

h2. Usage: ./manitest.rb

Manitest compiles a manifest using another hosts facts.

    -v, --verbose                    Output more information
    -d, --debug                      Output the full puppet debug
    -e, --environment                Override node environment
    -t, --tmpdir DIR                 Where to write temp files - defaults to /tmp
    -n, --node FILE                  YAML node file to use
    -c, --class CLASSA,CLASSB        node classes to use
    -h, --help                       Display this screen


h2. example runs:

h3. verbose mode

$ ./manitest.rb -n /var/lib/puppet/yaml/node/hostname.yaml -v
Setting up environment: development
Setting up facts:
The manifest compilation for hostname.yaml is OK
$ echo $?
0

h3. debug mode 

$  ./manitest.rb -n /var/lib/puppet/yaml/node/hostname.yaml -d -e global_puppetmaster
Setting up environment: global_puppetmaster
Setting up facts:
puppetmaster=>puppet
...
< a lot of facts info here >
/usr/bin/puppet --config /tmp/.tmp_puppet.conf --certname hostname --debug /tmp/.tmp_node.pp 2>&1
< a lot of puppet debug messages here >
Could not find class xyz in namespaces zzz at /etc/puppet/modules/zzz/manifests/init.pp:7 on node hostname
The manifest compilation for hostname is broken

h2. known limitations

It seems that this script will work only on the same architecture, as puppet internally tries to load the provides automatically, I'm not sure if its possible to run a Solaris manifest on a Linux host.

When not using external nodes, the class information must be specified manually with the -c option - e.g. ./manitest -c ntp::server,ssh::client etc.
