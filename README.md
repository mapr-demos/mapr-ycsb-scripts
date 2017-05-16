# Overview

This is a MapR-internal repo that contains scripts to assist with running
the Yahoo Cloud Serving Benchmark (YCSB) against MapR-DB, Cassandra
and HBase.

Using these scripts, you can:
* Manage running the YCSB client on a set of machines
* Manage copying the output and result files from each machine when workloads complete
* Create tables according to best practices
* Compute throughput and latency statistics for viewing or export to CSV
* Run multiple workloads with a single command
* Optionally gather 'nmon' data from the cluster nodes for offline analysis
* Optionally run YCSB against other databases like Cassandra or Apache HBase

The tools contained here serve as the authoritative copy for MapR staff -- when running
YCSB against MapR we recommend using these tools instead of copies or
forks found elsewhere to ensure the consensus best practices are followed.

# Before Running YCSB

If using YCSB with customers, it is important to set the right context
and not use a particular performance comparison as part of the buying decision,
because of the many varieties of workloads and tuning combinations that
are possible.

<bold>
Read the [internal document found here](https://drive.google.com/open?id=1wL_-uXnP3nAA2FpW3XktPxT70_cyYJN0hgAtODlVbCU) 
 before proceeding to test.  It contains some key points, settings and "gotchas" 
to know when running YCSB with a customer.
<bold>

# Prerequisites and Cluster Setup

## Prerequisites for running tests

Before starting the tests, you should have the following in place:

* A cluster of database nodes
* One or more client nodes if you do not intend to run the client on the database nodes
* A 'launcher node' should be designated which is where you will be running the scripts in this repo
* Set the environment variable $MAPR_YCSB_HOME to where you extracted these scripts, i.e. ~/mapr-ycsb-scripts

## Scripts to assist with cluster setup

The tools provided in the tools/ directory can assist with setting up a MapR or Cassandra cluster.  These tools assume you are running a benchmark on AWS and contain some EC2-specific items.  They also assume CentOS 7 and you will want to edit the top of these files to set 

```beforeinstall-prepmapr.sh``` should be run before the MapR software is installed.

```prepmapr.sh``` should be run after Mapr is installed.

```client_prepmapr.sh``` should be run to initialize the client nodes and will install the mapr-client package.

# Getting Started

## Download and install the tools

First clone this repo:

```
git clone https://github.com/mapr-demos/mapr-ycsb-scripts
```

Next get a copy of the YCSB binary distribution.  The below file is current at the time of this writing but you may want to use a later version if available.  These files are large (over 300MB) once uncompressed.

```
curl -L https://github.com/brianfrankcooper/YCSB/releases/download/0.11.0/ycsb-0.11.0.tar.gz | tar xvzf -
```

## Set up clustershell

The tools require that clustershell is installed.  You can install them in a ```virtualenv``` if needed, or just  `sudo yum -y install python-pip && sudo pip install -r clustershell-requirements.txt``` should do it.

For configuring clustershell, look at all the files in `dot_local` in this repo. Edit them as necessary Primarily, you need to edit the following:

`dot_local/etc/clustershell/clush.conf`: Set the remote username and your private keyfile location.

`dot_local/etc/clustershell/groups.d/local.cfg`: Edit the line starting with `all` to be a space-delimited list of the hostnames in your cluster. There are examples of different ways to write the list, but the `all` group must exist.

Then copy `dot_local` to `~/.local` (you can use the `-n` on cp to avoid clobbering existing files, just to be safe, remove if needed).

```
cp -nr dot_local ~/.local
```

If this all went according to plan, you should be able to run `clush -ab date` and get output similar to the following:

```
$ clush -ab date
---------------
172.16.2.[4-9] (6)
---------------
Sun Oct  9 12:21:01 EDT 2016
```

Clustershell is set up. Nice work.

## Set up ycsbrun.sh

Configuration of this script should happen by setting variables in
`env.sh` in the root of this repository. Comments in that file should
be self-explanatory.  A few deserve special mention:

* Note the variables CLUSH_NODE_GROUP and CLUSH_DB_NODE_GROUP.  These are the client and server node groups, respectively.  If you plan to run the clients on the nodes, you can set these to the same clush group.

* Set N_INSTANCES to the number of ycsb instances on each client node.  This is a multiplier for overall client instances.  For example, if you have 8 nodes and N_INSTANCES is set to 2, a total of 16 client instances will be running.

* The MAPR_CONTAINER_* variables are used only if you plan to run the clients in containers, otherwise can be left alone.

## Edit the workload specifications

Edit the files in YCSB-*/workloads to match the conditions of the tests that you want to run.  You will need to use one workload file for the 'load' phase, so make sure that if any time limitations are specified that they are not enabled in the workload file you plan to use for loading, otherwise the load will stop after the time period expires.

## Push the tools to the client nodes

Now that YCSB is unpacked, clustershell works, and these scripts are set up, you can push this stuff out to all the nodes.

```
clush -ac mapr-ycsb-scripts --dest=/home/centos/
clush -ac YCSB-* --dest=/home/centos/
```

## Examine runall.sh if running standard workloads

The script ```runall.sh``` is a wrapper around ```ycsbrun.sh``` that will run all of the common YCSB workloads, saving the files in between.  This is a handy way to launch the process which can take several hours, depending on your desired test configuration.

## Using ```nmon``` to gather resource statistics (optional)

To assist in debugging bottlenecks or other test issues, ```runall.sh```
will optionally launch ```nmon``` to gather resource utilization
statistics on each database node.  To do this you must set the NMON_*
variables to where you've placed the nmon binaries.  The nmon files are
copied into the results workload directory after the test completes and
can be viewed later with a GUI tool.  For more information on ```nmon```
see [this page](http://nmon.sourceforge.net/pmwiki.php).

# Running the tests

## Create the table

Having set up the above scripts you should have set a table name. Let's create it:

```
./createtable.sh maprdb 
```

Your output should be similar to (table name and NN may vary, of course):

```
$ ./createtable.sh
172.16.2.8: HBase Shell; enter 'help<RETURN>' for list of supported commands.
172.16.2.8: Type "exit<RETURN>" to leave the HBase Shell
172.16.2.8: Version 1.1.1-mapr-1602, rb861ca48ca25c69cf7f02b64b7a3d5c92dc310c5, Mon Feb 22 20:52:10 UTC 2016
172.16.2.8:
172.16.2.8: Not all HBase shell commands are applicable to MapR tables.
172.16.2.8: Consult MapR documentation for the list of supported commands.
172.16.2.8:
172.16.2.8: NN=12
172.16.2.8: 12
172.16.2.8: splits=(1..(NN-1)).map {|i| "user#{10000+i*(92924-10000)/NN}"}
172.16.2.8: ["user16910", "user23820", "user30731", "user37641", "user44551", "user51462", "user58372", "user65282", "user72193", "user79103", "user86013"]
172.16.2.8: create '/tables/ycsb4', 'family', SPLITS => splits
172.16.2.8: 0 row(s) in 0.2510 seconds
172.16.2.8:
172.16.2.8: Hbase::Table - /tables/ycsb4
```

This will use clustershell to pick a node at random from the cluster to create the table via the hbase shell. You need to pay attention to the output here, and make sure it completes successfully. Return code will be 0 even if it fails.

## Load the table

Execute the load phase, using all nodes of the cluster to load data.

```
./ycsbrun.sh maprdb load -p clientbuffering=true
```

Note the flag ```clientbuffering=true```, this is very important to achieve maximum performance with YCSB.

You should see lots of output.  It's helpful to run the tool in a tool
like [screen](https://www.gnu.org/software/screen/)  that will hold the
tty open (and log to a file if requested) so you can ensure the test
runs to completion.

Do not panic. Or do. It's a free country. Look for things that look
like errors.  As you might expect the tool is not perfect;  there may
be things that look like errors that are not errors.

May rows will be loaded into the table.  You should start seeing output like this:

```
2016-10-09 13:09:52:216 610 sec: 886342 operations; 1326.6 current ops/sec; est completion in 15 hours 45 minutes [INSERT: Count=13266, Max=509439, Min=1274, Avg=3729.79, 90=4083, 99=15807, 99.9=250751, 99.99=360447]
```

## Run your workload

You can run your workload as follows:

```
./ycsbrun.sh maprdb tran -p clientbuffering=true
```

"tran" is short for "transactions".

At the end of the run, you will get several files which contain the output
of the runs.  If you used the ```runall.sh``` script above, each test run
will be collated into an output directory containing the database name,
workload name and date/time of the run so you can collect several runs
over time.

## Running in containers

The commands "dockertran" and "dockerload" are for running the transactions and loading
phases, respectively, in docker containers.  These will launch the YCSB client instances
in docker on each client node.  The ```runall.sh``` script shows an example workflow of how
this is done, including making sure the tool and YCSB directories are mounted as volumes within
the client containers.

## Post-analysis:  generating statistics

Use the ```ycsbstats.sh``` script to generate statistics files based on the test output files.
This script can be run as ```./ycsbstats.sh <test_dir>``` to post-process all of the files in
a test directory.  The output of this script is a .txt file containing the overall throughput
combined, and a .csv file with a snapshot of throughput (ops/sec) and latency every few seconds.
This can be imported into a tool like Excel for further analysis.

