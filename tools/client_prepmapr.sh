#!/bin/bash

source $MAPR_YCSB_HOME/env.sh
EPELREPO='http://download.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-9.noarch.rpm'
PKGADD='yum -y install'
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
clush --options='-t -t' -g \
    $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo yum -y localinstall jre-8u60-linux-x64.rpm

clush --options='-t -t' -g \
    $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo cp maprtech.repo /etc/yum.repos.d/
clush --options='-t -t' -g \
    $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo yum -y install mapr-client.x86_64

# add some useful packages
clush --options='-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD dstat iperf wget
clush -o '-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER wget $EPELREPO
clush -o '-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo rpm -Uvh epel-release-7*.rpm

# copy over the tools
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -c $TOOL_HOME --dest=$REMOTE_COPYTO
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -c $YCSB_HOME --dest=$REMOTE_COPYTO

# copy over the MapR-DB jars -- pick one of the db nodes as the source
# because these are not installed on the client
D=$(mktemp -d)
F=$(clush -N -q -g $CLUSH_DB_NODE_GROUP --pick=1 ls /opt/mapr/hbase/hbase-$MAPR-HBASE-VERSION/lib/hbase-c\*)
for j in $F; do
	clush -N -q -g $CLUSH_DB_NODE_GROUP --pick=1 --rcopy $j --dest=$D
done

# delete the old jars first
clush -g $CLUSH_NODE_GROUP -l \
    $SSH_REMOTE_USER rm -f $YCSB_HOME/hbase10-binding/lib/hbase-c\*.jar

for file in $D/*; do
	NEWF=$(echo $file | sed -e 's/.jar.*/.jar/')
	mv $file $NEWF
	clush -g $CLUSH_NODE_GROUP -l \
		$SSH_REMOTE_USER -c $NEWF \
		--dest=$YCSB_HOME/hbase10-binding/lib
done

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

# take in the new conf
clush -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' sudo sysctl --system

