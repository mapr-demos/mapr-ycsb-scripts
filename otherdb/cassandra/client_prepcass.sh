#!/bin/bash

source env.sh
clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP -c /home/centos/jre-8u60-linux-x64.rpm --dest=/home/centos/
clush --options='-t -t' -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER sudo yum -y localinstall jre-8u60-linux-x64.rpm
