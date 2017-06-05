#!/bin/bash

# prepare the base image instances for a mapr install
# BEFORE mapr is installed
#
# before running, edit the variables at the top of this file.
#
# this script allows you to install the packages on the required nodes,
# then run 'configure.sh' and 'disksetup -W 1 -F /tmp/disks.txt' on 
# each node to complete the installation
#
# also need to set the passwd for the mapr user

source $MAPR_YCSB_HOME/env.sh

MAPRREPO_KEY='http://package.mapr.com/releases/pub/maprgpg.key'
EPELREPO='http://download.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-9.noarch.rpm'
PKGADD='yum -y install'
PKGADD_LOCAL='yum -y localinstall'
MKDISKSH=$TOOL_HOME/tools/mkdisk.sh

# this creates the disks.txt input file to disksetup
DISKSTXT=$(mktemp)
cat >> $DISKSTXT << __EOF
/dev/nvme0n1p5
/dev/nvme0n1p6
__EOF

# unmount the ephemeral disk
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'sudo umount /mnt'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    "sudo sed -i /etc/fstab -e \
    's/\/dev\/xvdf/#\/dev\/xvdf/'"

# add wget
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD wget

# add repos
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $MAPR_YCSB_HOME/tools/maprtech.repo --dest=/tmp
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo cp /tmp/maprtech.repo /etc/yum.repos.d/
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo \
    rpm --import $MAPRREPO_KEY
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER wget $EPELREPO
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo rpm -Uvh epel-release-7*.rpm

# add java
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'wget --no-cookies --no-check-certificate --header \
	"Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
	http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm'
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD_LOCAL jre-8u131-linux-x64.rpm

# add mapr user
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo groupadd -g 5000 mapr
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo useradd -m -c 'MapR' -g mapr mapr

# partition the nvme disk
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $MKDISKSH --dest=/tmp/
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo bash /tmp/mkdisk.sh

# copy the mapr disk info
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $DISKSTXT --dest=/tmp/disks.txt

# install the base package on all nodes
clush -o '-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD mapr-fileserver
