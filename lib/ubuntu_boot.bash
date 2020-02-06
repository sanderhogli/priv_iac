#!/bin/bash -v

# upgrade
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -o "Dpkg::Options::=--force-confold" dist-upgrade -y --force-yes

# install Puppet agent
tempdeb=$(mktemp /tmp/debpackage.XXXXXXXXXXXXXXXXXX) || exit 1

#i=0;ret=1;
#while [ "$i" -lt "5" ] && [ "$ret" ]; do
  wget -O "$tempdeb" https://apt.puppetlabs.com/puppet6-release-bionic.deb
#  ret="$?"
#  sleep 10
#  let $i++
#done
#if [ "$ret" ]; then # All attempts to download file failed, instruct clound-init to restart and try again
#  exit 1003
#fi

dpkg -i "$tempdeb"
apt-get update
apt-get -y install puppet-agent
echo "$(/opt/puppetlabs/bin/facter networking.ip) $(hostname).node.consul $(hostname)" >> /etc/hosts
echo "manager_ip_address manager.node.consul manager" >> /etc/hosts
/opt/puppetlabs/bin/puppet config set server manager.node.consul --section main
/opt/puppetlabs/bin/puppet config set runinterval 300 --section main
/opt/puppetlabs/bin/puppet resource service puppet ensure=running enable=true
