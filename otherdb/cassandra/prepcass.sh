#!/bin/bash

# install Cassandra on a cluster
#
# before running, edit the variables at the top of this file
#
# assumes Centos 7.x and cassandra 3.10

source $MAPR_YCSB_HOME/env.sh
DISKS="/dev/nvme0n1 /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1"
PKGADD='yum -y install'
REMOTE_COPYTO='/home/centos'
CASS_PKG="http://apache.org/dist/cassandra/3.10/apache-cassandra-3.10-bin.tar.gz"
EPELREPO='https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm'

# set to i.e. 'md0' if using RAID below
CASS_DISK="md0"

# set this to md0 if RAIDing disks together
DO_RAID=true

# local files to be copied to cluster machines
CASS_CONFIG_FILE=$TOOL_HOME/otherdb/cassandra/cassandra.yaml
LIMITS_FILE=$TOOL_HOME/otherdb/cassandra/cassandra-limits.conf
RAID_SCRIPT=$TOOL_HOME/otherdb/cassandra/raid_ephemeral.sh
CASS_SYSCTL_FILE=$TOOL_HOME/otherdb/cassandra/cassandra.conf
SYSCTL_CONF_FILE=$TOOL_HOME/otherdb/cassandra/sysctl.conf

# install java 8, maven and a few other pkgs
echo "installing prereqs"
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD wget dstat
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER wget $EPELREPO
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo rpm -Uvh epel-release-*.rpm
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'wget --no-cookies --no-check-certificate --header \
	"Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
	http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm'
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD_LOCAL jdk-8u131-linux-x64.rpm

clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo wget \
	http://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O \
        /etc/yum.repos.d/epel-apache-maven.repo
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD apache-maven

# optionally RAID0 the disks together
if [ "$DO_RAID" = "true" ]; then
	echo "preparing ephemeral disks"
	clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $RAID_SCRIPT --dest=/tmp/
	clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP \
	    -l $SSH_REMOTE_USER sudo bash /tmp/raid_ephemeral.sh -d \"$DISKS\"
fi

# add cassandra user and group
echo "making users"
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo groupadd cassandra
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo adduser -g cassandra cassandra

# install cassandra binary distribution
echo "downloading and installing files"
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER wget $CASS_PKG
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo tar xvfz apache-cassandra-3.10-bin.tar.gz -C /mnt
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo chgrp -R cassandra /mnt/apache-cassandra-3.10
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo chown -R cassandra /mnt/apache-cassandra-3.10

# uncomment this to use packages instead
# clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
# 'echo "deb http://www.apache.org/dist/cassandra/debian 39x main" \
# 	| sudo tee -a /etc/apt/sources.list.d/cassandra.sources.list'

# disable swap
echo "disabling swap"
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo swapoff --all

# put in a host entry for the internal interface
echo "adding a host entry"
clush -g $CLUSH_DB_NODE_GROUP --options='-t -t' -l $SSH_REMOTE_USER \
    "hostname -i | xargs echo casshost | awk ' { print \$2, \$1 } ' | sudo tee -a /etc/hosts"

# distribute the config file
echo "distributing config file"
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $CASS_CONFIG_FILE --dest=/tmp/cass.new
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP --options='-t -t' \
    sudo cp /mnt/apache-cassandra-3.10/conf/cassandra.yaml /tmp/cassandra.bak
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP --options='-t -t' \
    sudo cp /tmp/cass.new /mnt/apache-cassandra-3.10/conf/cassandra.yaml

# set proper limits
echo "(un)setting limits"
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $LIMITS_FILE --dest=/tmp/cassandra-limits.conf
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'sudo cp /etc/security/limits.conf /tmp/baklimits.conf'
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'sudo cp /tmp/cassandra-limits.conf /etc/security/limits.conf'
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'sudo sysctl -p'
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $CASS_SYSCTL_FILE --dest=/tmp/cassandra.conf
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'sudo cp /tmp/cassandra.conf /etc/sysctl.d/'
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $SYSCTL_CONF_FILE --dest=/tmp/sysctl.conf
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'sudo cp /tmp/sysctl.conf /etc/sysctl.conf'
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'sudo sysctl --system'

# copy over all the scripts and tools
echo "copying scripts and tools"
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $YCSB_HOME --dest=$YCSB_HOME
clush -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $TOOL_HOME --dest=$TOOL_HOME

# set optimal IO parameters for RAID device or disk
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER export CASS_DISK=$CASS_DISK \
	echo 1 | sudo tee /sys/block/$CASS_DISK/queue/nomerges'
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER export CASS_DISK=$CASS_DISK 'echo 8 | \
    sudo tee /sys/block/$CASS_DISK/queue/read_ahead_kb'
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP \
    -l $SSH_REMOTE_USER export CASS_DISK=$CASS_DISK 'echo deadline | \
    sudo tee /sys/block/$CASS_DISK/queue/scheduler'

# turn off transparent huge page compaction
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'echo never | \
    sudo tee /sys/kernel/mm/transparent_hugepage/defrag | \
    sudo tee /sys/kernel/mm/transparent_hugepage/enabled | \
    sudo tee -a /etc/rc.local'

# copy over the tools
clush a -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $TOOL_HOME --dest=$REMOTE_COPYTO
clush a -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -c $YCSB_HOME --dest=$REMOTE_COPYTO

# start cassandra
#clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'nohup sudo -u cassandra /mnt/apache-cassandra-3.10/bin/cassandra'
