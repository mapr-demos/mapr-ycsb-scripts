#!/bin/bash

# perform most (not all) steps prepare an EC2 node to run YCSB 
#
# before running, edit $DISKS, $PKGADD, $REMOTE_COPYTO to set
# to your environment.  $DISKS should be the disks allocated to
# MapR-FS (just the disk device not including partitions).
#
# this script assumes: 
# - MapR is installed and running on all the nodes
# - only tested with CentOS 7.x, may break on other OS's

source $MAPR_YCSB_HOME/env.sh
DISKS="nvme0n1"
PKGADD='yum -y install'
REMOTE_COPYTO='/home/centos'
NMON=/home/centos/nmon/nmon_x86_64_centos7
REMOTE_NMON=/home/centos/nmon/
NMON_DIR=/home/centos/nmon_logs
SPS_PER_INST=2

# add some useful packages
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo $PKGADD dstat

# disable swap
echo "disabling swap"
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo swapoff --all

echo "refreshing systemctl"
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER sudo systemctl daemon-reload

# turn off transparent huge page compaction
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'echo never | \
    sudo tee /sys/kernel/mm/transparent_hugepage/defrag' 
clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER 'echo \
    "echo never > /sys/kernel/mm/transparent_hugepage/defrag" | \
     sudo tee -a /etc/rc.local'

# add disk/mfs settings for SSDs according to:
# http://doc.mapr.com/display/MapR/Best+Practices
for d in $DISKS; do
    CMDSTR='echo noop | sudo tee '
    CMDSTR+=/sys/block/$d/queue/scheduler
    clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER "$CMDSTR"
done

clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'echo mfs.ssd.trim.enabled=1 | sudo tee -a /opt/mapr/conf/mfs.conf'

clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'echo mfs.disk.iothrottle.count=50000  | sudo tee -a /opt/mapr/conf/mfs.conf'

clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'echo mfs.ssd.trim.enabled=1 | sudo tee -a /opt/mapr/conf.new/mfs.conf'

clush --options='-t -t' -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    'echo mfs.disk.iothrottle.count=50000  | sudo tee -a /opt/mapr/conf.new/mfs.conf'

clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    "sudo sed -i /opt/mapr/conf/warden.conf -e \
    's/#service.command.mfs.heapsize.percent=35/service.command.mfs.heapsize.percent=85/'"

clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    "sudo sed -i /opt/mapr/conf.new/warden.conf -e \
    's/#service.command.mfs.heapsize.percent=35/service.command.mfs.heapsize.percent=85/'"

clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    sudo -u mapr maprcli config save -values {multimfs.numsps.perinstance:$SPS_PER_INST}

# restart warden to take it all in
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' 'sudo service mapr-warden restart'

# copy over the tools
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $TOOL_HOME --dest=$REMOTE_COPYTO
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $YCSB_HOME --dest=$REMOTE_COPYTO

# copy over the MapR-DB jars 
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER rm $YCSB_HOME/hbase10-binding/lib/hbase-c\*.jar
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER \
    cp /opt/mapr/hbase/hbase-$MAPR_HBASE_VERSION/lib/hbase-c\* \
    $YCSB_HOME/hbase10-binding/lib

# copy nmon binaries
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER mkdir -p $NMON_DIR $REMOTE_NMON
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -c $NMON --dest=$REMOTE_NMON

# a bunch of sysctls recommended by eng.
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.rmem_max=16777216'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.rmem_default=16777216'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.wmem_max=16777216'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.core.wmem_default=16777216'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.ipv4.tcp_rmem=16777216'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.ipv4.tcp_wmem=16777216'
clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
    'sudo sysctl -w net.ipv4.tcp_mem="16777216 16777216 16777216"'

# uncomment this to start the docker service
# clush -g $CLUSH_DB_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' 'sudo service docker start'
