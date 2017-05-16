#!/bin/bash

source $MAPR_YCSB_HOME/env.sh
TFILE=$(mktemp)

cat << EOF > $TFILE
[maprtech]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/v5.2.1/redhat/
enabled=1
gpgcheck=0
protect=1

[maprecosystem]
name=MapR Technologies
baseurl=http://package.mapr.com/releases/MEP/MEP-3.0/redhat
enabled=1
gpgcheck=0
EOF

clush -g $CLUSH_NODE_GROUP -c $TFILE --dest=/home/centos/maprtech.repo

clush -g $CLUSH_NODE_GROUP -c /home/centos/jre-8u60-linux-x64.rpm --dest=/home/centos/
clush --options='-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo yum -y localinstall jre-8u60-linux-x64.rpm

clush --options='-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo cp maprtech.repo /etc/yum.repos.d/
clush --options='-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo yum -y install mapr-client.x86_64

# copy over the tools
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -c $TOOL_HOME --dest=$REMOTE_COPYTO
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -c $YCSB_HOME --dest=$REMOTE_COPYTO

# copy over the MapR-DB jars 
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER rm $YCSB_HOME/hbase10-binding/lib/hbase-c\*.jar
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER cp /opt/mapr/hbase/hbase-$MAPR_HBASE_VERSION/lib/hbase-c\* \
	$YCSB_HOME/hbase10-binding/lib

# a bunch of sysctls recommended by eng.
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.rmem_max=16777216'
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.rmem_default=16777216'
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.wmem_max=16777216'
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.wmem_default=16777216'
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.ipv4.tcp_rmem=16777216'
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.ipv4.tcp_wmem=16777216'
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.ipv4.tcp_mem="16777216 16777216 16777216"'
