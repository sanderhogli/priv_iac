#!/bin/bash -v

export DEBIAN_FRONTEND=noninteractive

# install Puppet and make sure its services are stopped
tempdeb=$(mktemp /tmp/debpackage.XXXXXXXXXXXXXXXXXX) || exit 1

i=0;
wget -O "$tempdeb" https://apt.puppetlabs.com/puppet6-release-bionic.deb
ret="$?"
while [ "$i" -lt "5" ] && [ "$ret" -ne "0" ]; do
  wget -O "$tempdeb" https://apt.puppetlabs.com/puppet6-release-bionic.deb
  ret="$?"
  let "i++"
done
if [ "$ret" -ne "0" ]; then # All attempts to download file failed, instruct clound-init to restart and try again
  exit 1003
fi


dpkg -i "$tempdeb"
apt-get update
apt-get -y install puppetserver git pwgen
/opt/puppetlabs/bin/puppet resource service puppet ensure=stopped enable=true
/opt/puppetlabs/bin/puppet resource service puppetserver ensure=stopped enable=true

# configure local name resolution while waiting for DNS to work
echo "$(/opt/puppetlabs/bin/facter networking.ip) $(hostname).node.consul $(hostname)" >> /etc/hosts

# configure Puppet to run every five minutes
/opt/puppetlabs/bin/puppet config set server manager.node.consul --section main
/opt/puppetlabs/bin/puppet config set runinterval 300 --section main

# configure puppetserver to accept all new agents automatically
/opt/puppetlabs/bin/puppet config set autosign true --section master
/opt/puppetlabs/bin/puppetserver ca setup

# install and configure r10k
/opt/puppetlabs/bin/puppet module install puppet-r10k
cat <<EOF > /var/tmp/r10k.pp
class { 'r10k':
  sources => {
    'puppet' => {
      'remote'  => 'https://github.com/sanderhogli/control-repo-1.git',
      'basedir' => '/etc/puppetlabs/code/environments',
      'prefix'  => false,
    },
  },
}
EOF
/opt/puppetlabs/bin/puppet apply /var/tmp/r10k.pp

# deploy the Puppet code based on the control repository
# (roles, profiles, hieradata and all component modules)
r10k deploy environment -p

# copy global Hiera config in place (this is needed because its only
# in the global Hiera config it is allowed to use absolute path in datadir)
cd /etc/puppetlabs/code/environments/production/ || exit
cp global_hiera.yaml /etc/puppetlabs/puppet/hiera.yaml

# if additional first time scripts needed, e.g. do
bash ./new_keys_and_passwds.bash
#
# only needed for now is some module "hacks"
/opt/puppetlabs/puppet/bin/gem install lookup_http
/opt/puppetlabs/bin/puppetserver gem install lookup_http
cd /etc/puppetlabs/code/environments/production/modules || exit
git clone https://github.com/ppouliot/puppet-dns.git
mv puppet-dns dns

# start puppetserver and let puppet configure the rest of manager
/opt/puppetlabs/bin/puppet resource service puppetserver ensure=running enable=true
/opt/puppetlabs/bin/puppet agent -t # request certificate
/opt/puppetlabs/bin/puppet agent -t # configure manager
/opt/puppetlabs/bin/puppet resource service puppet ensure=running enable=true
