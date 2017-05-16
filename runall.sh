#!/bin/bash
#
# Run all the standard YCSB workloads A-F.
#
# Pre-conditions before running
# -----------------------------
# 
# - Assumes the load phase was done beforehand.
# 
# - Assumes 'operationcount' !=0 (in the YCSB workload
#   file or specified on the command line)
#   so the workload does not run continuously.  Another way
#   to ensure this is to set 'maxexecutiontime'.
#
# - Set $WHICHDB in this file to set the correct YCSB back-end
#
# - Set $ENVSH and $ENVSH_REMOTE to the paths of env.sh on the local
#   and remote hosts, respectively
#
# - Set $NMON to the path to the 'nmon' utility:  see http://nmon.sourceforge.net
# 
# - Set $NMON_DIR to the path where you want the nmon output logs.
#
# Any command line args (such as '-p xyz') are passed to
# ycsbrun.sh for the 'tran' phase.
#

source env.sh

ENVSH=/home/centos/mapr-ycsb-scripts/env.sh
ENVSH_REMOTE=/home/centos/mapr-ycsb-scripts/env.sh
#WHICHDB=cassandra2-cql
WHICHDB=maprdb

USE_NMON=true
NMON=/home/centos/nmon/nmon_x86_64_centos7
NMON_DIR=/home/centos/nmon_logs

USE_DOCKER=false

for w in a b c d e f; do
	if [ "$USE_DOCKER" = "true" ]; then
		echo "killing all existing containers"
		clush -q -g $CLUSH_NODE_GROUP -l $SSH_REMOTE_USER -o '-t -t' \
			"sudo docker ps -q  | xargs -r sudo docker kill"
	else
		echo "killing off all jobs"
		$TOOL_HOME/ycsbrun.sh $WHICHDB kill
	fi
	echo "clearing caches on db nodes"
	clush -q -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -o '-t -t' \
	    "echo 3 | sudo tee /proc/sys/vm/drop_caches" > /dev/null 2>&1 
	if [ "$USE_NMON" = "true" ] && [ x"$NMON_DIR" != x ]; then
		echo "starting/restarting nmon on db nodes"
		clush -q -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -o '-t -t' "sudo pkill nmon"
		clush -q -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -o '-t -t' \
		    "cd $NMON_DIR && sudo rm -f *.nmon"
	fi
	echo "copying files for workload $w"
	sed -i $ENVSH -e s/workload[abcdef]/workload$w/
	clush -q -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP -c $ENVSH --dest=$ENVSH_REMOTE
	clush -q -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP -c $YCSB_HOME/workloads/workload$w \
		--dest=$YCSB_HOME/workloads/workload$w
	clush -q -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP \
	    rm -f $YCSB_HOME/$FILENAME_BASE.stats
	echo "running workload $w"
	if [ "$USE_NMON" = "true" ]; then
	    clush -q -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP -o \
	        '-t -t' "cd $NMON_DIR && sudo $NMON -f -s 10"
	fi
	if [ "$USE_DOCKER" = "true" ]; then
		$TOOL_HOME/ycsbrun.sh $WHICHDB dockertran $*
	else
		$TOOL_HOME/ycsbrun.sh $WHICHDB tran $*
	fi
	RESULTDIR_FORMAT=`date '+%Y%m%d_%T'`
	DIRSTR=$WHICHDB
	DIRSTR+='_'
	DIRSTR+=workload_
	DIRSTR+=$w
	DIRSTR+='_'
	if [ "$USE_DOCKER" = "true" ]; then
		DIRSTR+=docker
	else
		DIRSTR+=nodocker
	fi
	DIRSTR+='_'
	DIRSTR+=$RESULTDIR_FORMAT
	mkdir -p $TOOL_HOME/$DIRSTR
	echo "workload $w complete, copying result files to directory $DIRSTR"
	if [ "$USE_NMON" = "true" ]; then
		echo "gathering nmon data from db nodes"
		clush -q -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP \
		    -o '-t -t' "sudo pkill nmon"
  		clush -q -l $SSH_REMOTE_USER -g $CLUSH_DB_NODE_GROUP \
		    --rcopy $NMON_DIR/*.nmon --dest .
		if ls *nmon* 1> /dev/null 2>&1; then
			# fixup weird behavior of clush rcopy and wildcards
			for f in *nmon*; do
				newf=`echo $f | sed -e 's/\*\.//'`
				mv $f $newf
				mv $newf $DIRSTR
			done
		fi
	fi
	clush -q -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP \
	    -o '-t -t' "sudo chmod 644 /opt/mapr/logs/mfs.log*"
	$TOOL_HOME/ycsbrun.sh $WHICHDB copy
	mv $FILENAME_BASE.out.* $DIRSTR
	mv $FILENAME_BASE.stats.* $DIRSTR
	if ls mfs.log* 1> /dev/null 2>&1; then
		mv mfs.log* $DIRSTR
	fi
	if ls $FILENAME_BASE.maprcli* 1> /dev/null 2>&1; then
		mv $FILENAME_BASE.maprcli* $DIRSTR
	fi
	if ls $FILENAME_BASE.hadoop* 1> /dev/null 2>&1; then
		mv $FILENAME_BASE.hadoop* $DIRSTR
	fi
	if ls $FILENAME_BASE.nodetool* 1> /dev/null 2>&1; then
		mv $FILENAME_BASE.nodetool* $DIRSTR
	fi
	if ls $FILENAME_BASE.nodetool* 1> /dev/null 2>&1; then
		mv $FILENAME_BASE.nodetool* $DIRSTR
	fi
	echo "done copying files"
done
echo "tests completed"
