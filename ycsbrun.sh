#!/bin/bash


#Simple script to perform a variety of YCSB related actions.
#by design the script has little intelligence. I don't want to obscure what YCSB is really doing.
#this script simply helps the user avoid a lot of annoying typing.

#these scripts assume clush is installed with passwordless ssh configured.
#these scripts assume there is a clush group 'all' although you can change that to any group you like

#the output from ycsb is written to $TOOL_HOME on all nodes. This must NOT be a shared directory or they will overwrite
#each other.

source env.sh

# this is the number of threads used for transactional workloads
if [ -z $TRAN_THREADS ]; then
  TRAN_THREADS=75
fi
# this is the number of threads used for  load
if [ -z $LOAD_THREADS ]; then
  LOAD_THREADS=50
fi


function getdatanodes {
  #determine the nodes that are used for various commands using clush
  #you can change to 'data' to 'all' if all nodes store tables

  #this is a function because I only need to execute it for the initial commands and it doesn't have
  #to be executed when the functions are running on a data node where clush may not be available
  DATANODES=`clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP -N hostname`
  if [ $? != 0 ]; then
    echo "clush group '$CLUSH_NODE_GROUP' not defined. Please define."
    exit
  fi
  #remove newlines
  DATANODES=`echo $DATANODES |tr  '[:space:]' ' ' `
  FIRST_DATANODE="${DATANODES%% *}"
  #if [[ $FIRST_DATANODE =~ ip-[0-9]+-[0-9]+-[0-9]+-[0-9] ]]; then
    ## we are most likely running on EC2, try to get external hostnames
  #  DATANODES=`clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP -N curl -s http://169.254.169.254/latest/meta-data/public-ipv4`
  #  DATANODES=`echo $DATANODES |tr  '[:space:]' ' ' `
  #  FIRST_DATANODE="${DATANODES%% *}"
  #fi
}





#functions

function func_copy() {
  #copy ycsb results. Notice that this is the only command that depends on the mapr client
  #as such it has a special option to run remotely

  echo copying YCSB results files to current directory
  for ni in $(seq 1 $N_INSTANCES)
  do
    clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP --rcopy $YCSB_HOME/$FILENAME_BASE.stats.$ni --dest .
    clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP --rcopy $TOOL_HOME/$FILENAME_BASE.out.$ni --dest .
  done

  if [ "$TYPE" = "maprdb" ]; then 
    #copy up to 3 of the most recent MFS-5 log files (MapR-DB output)
    #this may generate spurious errors if not there
    #this could be a lot of data
    echo copying MFS log files which can be very large. Consider disabling if space is an issue.
    #echo NOT copying MFS log files. Edit script if you want to preserve.
    clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP --rcopy /opt/mapr/logs/mfs.log-5{,.1,.2} --dest . 2>&1 |grep -v "No such file or directory"| grep -v "exited with exit code 1"
    ls mfs.log-5* > /dev/null
    if [ $? != 0 ]; then
      echo Failed to copy MFS log files. Proceeding anyway.
    else
      gzip mfs.log*
    fi

    echo collecting table information via maprcli and hadoop mfs
    TABLEINFOFILE=$FILENAME_BASE.maprcli.table.info
    REGIONFILE=$FILENAME_BASE.maprcli.table.region.list
    MFSFILE=$FILENAME_BASE.hadoop.mfs
    maprcli table info -path $TABLE -json > $TABLEINFOFILE
    maprcli table region list -path $TABLE -json > $REGIONFILE
    echo "======================" >> $REGIONFILE
    echo "summary info" >> $REGIONFILE
    echo "======================" >> $REGIONFILE
    grep primarynode $REGIONFILE |sort |uniq  -c >> $REGIONFILE
    hadoop mfs -lss $TABLE > $MFSFILE
  elif [ "$TYPE" = "cassandra2-cql" ]; then 
    STATUSFILE=$FILENAME_BASE.nodetool.status
    clush -l $SSH_REMOTE_USER --pick=1 -g $CLUSH_NODE_GROUP nodetool status > $STATUSFILE
  else
    echo "Not copying anything for HBase (TBD)"
  fi
}

function func_tran() {
  #run YCSB on all nodes using one
  getdatanodes

  echo "DATANODES:" $DATANODES

  echo "Running YCSB test on these nodes: $DATANODES (using $TYPE with $TABLE)"

  RUNCMD=tranone
  TTYFLAG=
  if [ "$USE_DOCKER" = true ]; then
	  echo "Using docker container..."
	  RUNCMD=dockertranone
	  TTYFLAG='-t -t'
  fi

  for node in $DATANODES
  do
    for ni in $(seq 1 $N_INSTANCES)
    do
      set -x
      #hide the SLF4J error message
      ssh $TTYFLAG $SSH_REMOTE_USER@$node \
      "cd $TOOL_HOME; WORKLOAD=$WORKLOAD $TOOL_HOME/ycsbrun.sh $TYPE $RUNCMD $ni $* |grep -v SLF4J" &
      set +x
    done
  done

  echo Waiting for completion
  wait
}

function func_one() {
  mode=$1
  shift
  myinst=$1
  shift
  echo "executing single YCSB client, type: $TYPE, table: $TABLE, mode: $mode, instnum: $myinst"

  # starts an instance of YCSB, can be multiple per machine

  if [ "$mode" = "load" ]; then 
	threads=$LOAD_THREADS
  else
	threads=$TRAN_THREADS
  fi

  CPCMD='hbase classpath'
  if [ "$USE_DOCKER" = true  ]; then
	  # XXX
	  # this is maintained for compatibility -- it's awkward that
	  # 'load' and 'loadone' are accepted as arguments but 'tran' and
	  # 'tranone' actually mean 'run', because of the arguments to 
	  # ycsb.  
	  CPCMD='mapr classpath'
	  if [ "$mode" = "run" ]; then
		mode='tranone'
	  else
	  	mode+='one'
	  fi
	  if [ "$TYPE" != "maprdb" ]; then
	  	echo "*** ERROR:  docker mode supported only for maprdb type"
	  	exit
	  fi
  fi

  #leverages newer ycsb scripts (0.7.x and later)
  if [ "$TYPE" = "cassandra2-cql" ]; then
    # we only need to supply one host here, the client will discover the others
    (cd $YCSB_HOME && $YCSB_HOME/bin/ycsb $mode cassandra2-cql -threads \
        $threads -P $WORKLOAD \
        -cp /YCSBRUN.FAKE -p exportfile=$YCSB_HOME/$FILENAME_BASE.stats.$myinst -s $* 2>&1) | \
        tee $FILENAME_BASE.out.$myinst; egrep -v "\[[A-Z\-]+\], >?[0-9]+, [0-9]+" \
        $YCSB_HOME/$FILENAME_BASE.stats.$myinst
  elif [ "$USE_DOCKER" = true ]; then
	   sudo docker run -w $TOOL_HOME -t -i -a STDOUT -a STDIN -a STDERR \
	  	  -v $MAPR_CONTAINER_BASEDIR:$MAPR_CONTAINER_BASEDIR -e MAPR_CLUSTER=$CLUSTER_NAME \
		  -e MAPR_CLDB_HOSTS=$CLDB_HOSTS -e MAPR_CONTAINER_USER=$MAPR_CONTAINER_USER \
		  -e MAPR_CONTAINER_GROUP=$MAPR_CONTAINER_GROUP \
	          -e MAPR_CONTAINER_UID=$MAPR_CONTAINER_UID \
		  -e MAPR_CONTAINER_GID=$MAPR_CONTAINER_GID $MAPR_CONTAINER_IMAGE \
		  start $TOOL_HOME/drun.sh $TOOL_HOME maprdb $mode $*
  else
    (cd $YCSB_HOME && $YCSB_HOME/bin/ycsb $mode hbase10 -threads \
        $threads -P $WORKLOAD -p table=$TABLE -p columnfamily=$COLUMNFAMILY \
        -p exportfile=$YCSB_HOME/$FILENAME_BASE.stats.$myinst -s $* \
	-cp /YCSBRUN.FAKE:`hbase classpath` 2>&1) | \
        tee $FILENAME_BASE.out.$myinst; \
        egrep -v "\[[A-Z\-]+\], >?[0-9]+, [0-9]+" $YCSB_HOME/$FILENAME_BASE.stats.$myinst
  fi
}


function func_load() {
  #run YCSB load on all nodes using one
  getdatanodes

  echo "Running YCSB load on these nodes: $DATANODES (using $TYPE with $TABLE)"

  # override  these as needed
  numnodes=`echo $DATANODES |wc -w`
  recordcount=`grep ^recordcount $WORKLOAD  |egrep -o "[0-9]+"`

  insertstart=0
  insertcount=$((recordcount/$numnodes))

  echo "Loading a total of $recordcount records onto $numnodes nodes ($insertcount from each)"

  RUNCMD=loadone
  TTYFLAG=
  if [ "$USE_DOCKER" = true ]; then
	  echo "Using docker container..."
	  RUNCMD=dockerloadone
	  TTYFLAG='-t -t'
  fi

  for node in $DATANODES
  do
    set -x
    #hide the SLF4J error message
    echo sleeping 3 before starting $node
    sleep 3
    # always use 1 instance here, only use multi-inst for transactions
    ssh $TTYFLAG $SSH_REMOTE_USER@$node "cd $TOOL_HOME; WORKLOAD=$WORKLOAD $TOOL_HOME/ycsbrun.sh $TYPE $RUNCMD 1 -p insertstart=$insertstart -p insertcount=$insertcount $* |grep -v SLF4J" &
    set +x
    insertstart=$((insertstart + insertcount))
  done

  echo Waiting for completion
  wait
}

function func_status() {
  clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP -b tail -1 $TOOL_HOME/ycsb.out
  #clush -g $CLUSH_NODE_GROUP -b tail -1 $YCSB_HOME/ycsb.out
}

function func_kill_one() {
  #kill all but this script
  pids=$(pgrep -f YCSBRUN.FAKE | grep -v ^$$\$)
  kill $pids 2> /dev/null
  exit 0
}

function func_kill() {
  clush -l $SSH_REMOTE_USER -g $CLUSH_NODE_GROUP cd $TOOL_HOME \; ./ycsbrun.sh $TYPE killone
}


function func_usage() {
  echo "Usage: ycsbrun.sh <db type> <action> [additional arguments] where"
  echo "	<db type> is one of maprdb, hbase or cassandra2-cql"
  echo "	<action> is one of one, all, load, copy, status, kill"
  echo "		load - run a ycsb load on all nodes (load data - run first)"
  echo "		tran - run a ycsb test on all nodes"
  echo "                dockerload - same as load, but use the MapR PACC docker container"
  echo "                dockertran - same as tran, but use the MapR PACC docker container"
  echo "		loadone/tranone - run a single ycsb test from this node"
  echo "		status - report status of running ycsb tests"
  echo "		kill - kill running ycsb tests"
  echo "		copy - copy test results from a run to current directory"
  echo "Note that all, one, and load pass any additional arguments to the underlying YCSB tools"

  exit 1
}

##################
##MAIN
##################
  USEDOCKER=false
  TYPE=$1
  action=$2
  shift
  shift
  case "$TYPE" in 
    maprdb)
       ;;
    hbase)
       ;;
    cassandra2-cql)
       ;;
     *) 
        echo "ERROR: Unrecognized database type: " $TYPE
        func_usage
       ;;
  esac

  case "$action" in
    dockertranone) 
       USE_DOCKER=true
       # fall through
       ;&
    tranone) 
       func_one run $*
       ;;
    dockerloadone)
       USE_DOCKER=true
       # fall through
       ;&
    loadone)
       func_one load $*
       ;;
    dockertran)
       USE_DOCKER=true
       # fall through
       ;&
    tran)
       func_tran $*
       ;;
    dockerload)
       USE_DOCKER=true
       # fall through
       ;&
    load) 
       func_load $*
       ;;
    copy) 
       func_copy $*
       ;;
    status) 
       func_status $*
       ;;
    kill) 
       func_kill $*
       ;;
    killone) 
       func_kill_one $*
       ;;
     *) 
        echo "ERROR: Unrecognized action: " $action
        func_usage
       ;;
  esac
