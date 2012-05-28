# = Cookbook : stingray
#
# This cookbook/recipe installs and configures a stingray traffic manager,
# including joining clusters if necessary, and restores a backup 
# of configuration froma tar to the traffic manager.
#
# == Parameters:
# version::    The version of the traffix manage to install.
#       
# platform::   The OS to install the package to.
#
# installpath:: The location on the agent to install the traffic
#               manager to.
# password::   The password to use for the admin server, and to allow
#               other machine to connect to a cluster.
# config_tar:: The name of the backup tar holding the configuration,
#               /does/ include file ending.
# hostname::   The hostname of a node in the cluster that the traffic
#               managers will cluster on.
#
# == Sample Usage (attributes):
#
# node.default[:stingray][:version] = "8.0r1"
# node.default[:stingray][:platform] = "Linux"
# node.default[:stingray][:installpath] = "/space/my_traffic_manager"
# node.default[:stingray][:full_hostname] = "my_host.my_domain.com"
# node.default[:stingray][:password] = "my_password"
# node.default[:stingray][:config_tar] = "my_config.tar"
#

# collect attributes 
version = node[:stingray][:version]
platform = node[:stingray][:platform]
installpath = node[:stingray][:installpath]
password = node[:stingray][:password]
port = 9090 # hardcoded because we can't set the admin port...
full_hostname = node[:stingray][:full_hostname]
vservers = node[:stingray][:vservers]
pools = node[:stingray][:pools]

#config_tar = node[:stingray][:config_tar]

# get the hostname in a form ohai likes
my_hostname = full_hostname.split('.')[0]

dotversion = version.delete('.')

package = "ZeusTM_#{dotversion}_#{platform}"

# work out whether we are on a 64 or 32bit machine
if node["kernel"]["machine"] == "x86_64"
    _package = "#{package}-x86_64"
else
    _package = "#{package}-x86"
end

# different configure options depending if you are the 'host'
# of the cluster or not
if node["fqdn"] == my_hostname
    clusteroptionfirst = "c" # create
    clusteroptionsub = "l" #leave alone
else
    clusteroptionfirst = "s" # join existing
    clusteroptionsub = "s" # join existing
end

# pull out paths to change easily
tmp_folder = "/tmp"
package_path = "#{tmp_folder}/#{_package}" 
install_replayfile = "#{tmp_folder}/stingray_chef_install_replay"
final_conf_replay = "#{tmp_folder}/stingray_chef_final_conf_replay"
#config_tar_path = "#{tmp_folder}/stingray_chef_#{config_tar}"
#filterfile_path = "#{tmp_folder}/stingray_chef_filterfile"
basepath = "#{tmp_folder}/stingray_chef_confs"
confpath = "#{basepath}/conf"
extraconfpath = "#{basepath}/extraconf"

# download the package
cookbook_file "packagetar" do
    source "#{_package}.tgz"
    path "#{package_path}.tgz"
end

directory "#{package_path}" do
end

# untar the package
execute "tarzip" do
    command "tar -C #{tmp_folder} -zxvf #{package_path}.tgz"
    creates "#{package_path}/zinstall"
end


file "installreplay" do
    content "accept-license=accept\n" +
            "allow_non_root_install=y\n" +
            "zeushome=#{installpath}\n" +
            "zxtm!perform_initial_config=n\n"+
            "zxtm!upgrade_or_abort=u\n"
    path install_replayfile
end

# note the sting formatting
configure_content_template = "accept-license=accept\n"+
                             "fingerprints_ok=n\n"+
                             "start_at_boot=n\n"+
                             "zlb!admin_hostname=#{full_hostname}\n"+
                             "zlb!admin_password=#{password}\n"+
                             "zlb!admin_port=#{port}\n"+
                             "zlb!admin_username=admin\n"+
                             "zxtm!cluster=%s\n"+
                             "zxtm!clustertipjoin=y\n"+
                             "zxtm!fingerprints_ok=y\n"+
                             "zxtm!join_new_cluster=y\n"+
                             "zxtm!reconfigure_option=2\n"+
                             "admin!password=#{password}\n"+
                             "zxtm!group=nogroup\n"+
                             "zxtm!license_key=\n"+
                             "zxtm!unique_bind=n\n"+
                             "zxtm!user=nobody\n"

# decides which replay file to use, so that the host of the cluster either creates 
# the cluster on install, or stays in its current cluster on subsequent runs
if File.exist?("#{installpath}/start-zeus")
    conf_rep_final = configure_content_template % clusteroptionsub
else
    conf_rep_final = configure_content_template % clusteroptionfirst
end

# put the replayfile on disk
file "configurereplay" do
    content conf_rep_final
    path final_conf_replay
end

# run the install script if the traffic manager hasn't been installed already
execute "install" do
    cwd "#{package_path}"
    command "./zinstall --replay-from=#{install_replayfile}"
    creates "#{installpath}/zxtm-#{version}"
    path ["#{package_path}"]
end

# configure the traffic manager
# needs retry for clusters?
execute "configure" do
    cwd "#{installpath}/zxtm"
    command "./configure --nostart --replay-from=#{final_conf_replay}"
    path ["#{installpath}/zxtm"]
end

#cookbook_file "config_tar" do
#    source config_tar
#    path config_tar_path
#end

#file "filterfile" do
#    content "zxtms"
#    path filterfile_path
#end

# get a template conf directory
# purge = delete -> create

directory "delete_template_conf" do
    action :create
    path confpath
    recursive true
end

execute "copy_users" do
    command "cp -r #{installpath}/zxtm/.backup/conf/ #{basepath}"
end

# pull down the extra conf in the cookbook
remote_directory "extra_conf" do
    source "conf"
    overwrite true
    path confpath
end


# create version file
file "ver" do
    action :create
    path "#{confpath}/VERSION_#{version}"
end

# get user file from current conf
execute "copy_users" do
    command "cp #{installpath}/zxtm/conf/users #{confpath}"
end

# create vservers/pools
vservers.each do |key,value|
    template "#{confpath}/vservers/#{key}" do
        source "vserver.erb"
        variables(
            :vserver_pool => value["pool"],
            :vserver_port => value["port"]
        )
    end
end

pools.each do |key,value|
    template "#{confpath}/pools/#{key}" do
        source "pool.erb"
        variables(
            :pool_nodes => value["nodes"]
        )
    end
end

# Use zconf to full install the config.
execute "config_tar" do
    cwd "#{installpath}/zxtm/bin"
    command "./zconf diff #{confpath} | grep -v '=> identical' && ./zconf import #{confpath}"
    # deletes configuration that is there but shouldn't (only where the --full option is supported :
    # command "./zconf diff #{confpath} | grep -v '=> identical' && ./zconf import --full #{confpath}"
    path ["#{installpath}/zxtm/bin"]
end

#run all the things
execute "run" do
    cwd "#{installpath}"
    command "./start-zeus"
    path ["#{installpath}"]
end



