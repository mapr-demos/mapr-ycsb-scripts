#!/bin/bash

source $MAPR_YCSB_HOME/env.sh

EPELREPO='https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm'
REMOTE_COPYTO='/home/centos'
PKGADD='yum -y install'
PKGADD_LOCAL='yum -y localinstall'
NMON=/home/centos/nmon/nmon_x86_64_centos7
REMOTE_NMON=/home/centos/nmon/
NMON_DIR=/home/centos/nmon_logs

# add some useful packages
clush --options='-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD dstat iperf wget
clush -o '-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER wget $EPELREPO
clush -o '-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo rpm -Uvh epel-release-*.rpm

clush -o '-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER \
    'wget --no-cookies --no-check-certificate --header \
	"Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" \
	http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.rpm'
clush -o '-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD_LOCAL jdk-8u131-linux-x64.rpm

# copy over the tools
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -c $TOOL_HOME --dest=$REMOTE_COPYTO
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -c $YCSB_HOME --dest=$REMOTE_COPYTO

# copy nmon binaries
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER mkdir -p $NMON_DIR $REMOTE_NMON
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $NMON --dest=$REMOTE_NMON
