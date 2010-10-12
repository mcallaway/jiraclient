#! /usr/bin/python
#
# This feels like too much code for such a simple job.  But I'm finding
# it much easier to parse bhosts and bjobs output and ask for exactly
# what I'm interested in, rather than reading that output directly
# or using some shell, sed, awk, etc.
#

import copy
import logging, logging.handlers
import time
import subprocess
from optparse import OptionParser,OptionValueError
from operator import itemgetter,attrgetter
import pickle
import pprint
import sys
import time
import os
import re

name = "lsftool"
version = "0.7.1"

pp = pprint.PrettyPrinter(indent=4)
job_rx = re.compile("^(\d+) ")

# This is annoying, but all references that define the possible
# pending reason strings don't match what we see in reality.  So
# we define what the docs say, and manually add what we really see
# to the best of our ability.
pending_reasons_txt = '''
PEND_JOB_NEW, New job is waiting for scheduling
PEND_JOB_START_TIME, The job has a specified start time
PEND_JOB_DEPEND, Job dependency condition not satisfied
PEND_JOB_DEP_INVALID, Dependency condition invalid or never satisfied
PEND_JOB_MIG, Migrating job is waiting for rescheduling
PEND_JOB_PRE_EXEC, The job's pre-exec command exited with non-zero status
PEND_JOB_NO_FILE, Unable to access job file
PEND_JOB_ENV, Unable to set job's environment variables
PEND_JOB_PATHS, Unable to determine job's home/working directories
PEND_JOB_OPEN_FILES, Unable to open job's I/O buffers
PEND_JOB_EXEC_INIT, Job execution initialization failed
PEND_JOB_RESTART_FILE, Unable to copy restarting job's checkpoint files
PEND_JOB_DELAY_SCHED, The schedule of the job is postponed for a while
PEND_JOB_SWITCH, Waiting for re-scheduling after switching queue
PEND_JOB_DEP_REJECT, Event is rejected by eeventd due to syntax error
PEND_JOB_NO_PASSWD, Failed to get user password
PEND_JOB_MODIFY, Waiting for re-scheduling after parameters have been changed
PEND_JOB_REQUEUED, Requeue the job for the next run
PEND_SYS_UNABLE, System is unable to schedule the job.
PEND_JOB_ARRAY_JLIMIT, The job array has reached its running element limit
PEND_CHKPNT_DIR, Checkpoint directory is invalid
PEND_QUE_INACT, The queue is inactivated by the administrator
PEND_QUE_WINDOW, The queue is inactivated by its time windows
PEND_QUE_JOB_LIMIT, The queue has reached its job slot limit
# Added
PEND_QUE_JOB_LIMIT, Resource (slot) limit defined on queue has been reached
PEND_QUE_PJOB_LIMIT, The queue has not enough job slots for the parallel job
PEND_QUE_USR_JLIMIT, User has reached the per-user job slot limit of the queue
PEND_QUE_USR_PJLIMIT, Not enough per-user job slots of the queue for the parallel job
PEND_QUE_PRE_FAIL, The queue's pre-exec command exited with non-zero status
PEND_SYS_NOT_READY, System is not ready for scheduling after reconfiguration
PEND_SBD_JOB_REQUEUE, Requeued job is waiting for rescheduling
PEND_JOB_SPREAD_TASK, Not enough hosts to meet the job's spanning requirement
PEND_QUE_SPREAD_TASK, Not enough hosts to meet the queue's spanning requirement
PEND_QUE_WINDOW_WILL_CLOSE, Job will not finish before queue's run window is closed
PEND_QUE_PROCLIMIT, Job no longer satisfies queue PROCLIMIT configuration
PEND_USER_JOB_LIMIT, The user has reached his/her job slot limit
PEND_UGRP_JOB_LIMIT, One of the user's groups has reached its job slot limit
PEND_USER_PJOB_LIMIT, The user has not enough job slots for the parallel job
PEND_UGRP_PJOB_LIMIT, One of user's groups has not enough job slots for the parallel job
PEND_USER_RESUME, Waiting for scheduling after resumed by administrator or user
PEND_USER_STOP, The job was suspended by the user while pending
# Added 2 more PEND_USER_STOP versions
PEND_USER_STOP, The job was suspended by the user while pending.
PEND_USER_STOP, Job was suspended by the user while pending.
PEND_ADMIN_STOP, The job was suspended by LSF admin or root while pending
PEND_NO_MAPPING, Unable to determine user account for execution
PEND_RMT_PERMISSION, The user has no permission to run the job on remote host/cluster
PEND_HOST_RES_REQ, Job's resource requirements not satisfied
PEND_HOST_NONEXCLUSIVE, Job's requirement for exclusive execution not satisfied
PEND_HOST_JOB_SSUSP, Higher or equal priority jobs suspended by host load
PEND_SBD_GETPID, Unable to get the PID of the restarting job
PEND_SBD_LOCK, Unable to lock host for exclusively executing the job
PEND_SBD_ZOMBIE, Cleaning up zombie job
PEND_SBD_ROOT, Can't run jobs submitted by root
PEND_HOST_WIN_WILL_CLOSE, Job will not finish on the host before queue's run window is closed
PEND_HOST_MISS_DEADLINE, Job will not finish on the host before job's termination deadline
PEND_FIRST_HOST_INELIGIBLE, The specified first exection host is not eligible for this job at this time
PEND_HOST_DISABLED, Closed by LSF administrator
PEND_HOST_LOCKED, Host is locked by LSF administrator
PEND_HOST_LESS_SLOTS, Not enough job slot(s)
PEND_HOST_WINDOW, Dispatch windows closed
PEND_HOST_JOB_LIMIT, Job slot limit reached
PEND_QUE_PROC_JLIMIT, Queue's per-CPU job slot limit reached
PEND_QUE_HOST_JLIMIT, Queue's per-host job slot limit reached
PEND_USER_PROC_JLIMIT, User's per-CPU job slot limit reached
PEND_UGRP_PROC_JLIMIT, User group's per-CPU job slot limit reached
PEND_HOST_USR_JLIMIT, Host's per-user job slot limit reached
PEND_HOST_QUE_MEMB, Not usable to the queue
PEND_HOST_USR_SPEC, Not specified in job submission
PEND_HOST_NO_USER, There is no such user account
PEND_HOST_ACCPT_ONE, Just started a job recently
PEND_LOAD_UNAVAIL, Load information unavailable
PEND_HOST_NO_LIM, LIM is unreachable now
PEND_HOST_QUE_RESREQ, Queue's resource requirements not satisfied
PEND_HOST_SCHED_TYPE, Not the same type as the submission host
PEND_JOB_NO_SPAN, Not enough processors to meet the job's spanning requirement
PEND_QUE_NO_SPAN, Not enough processors to meet the queue's spanning requirement
PEND_HOST_EXCLUSIVE, Running an exclusive job
PEND_HOST_LOCKED_MASTER, Host is locked by master LIM
PEND_SBD_UNREACH, Unable to reach slave batch server
PEND_SBD_JOB_QUOTA, Number of jobs exceeds quota
PEND_JOB_START_FAIL, Failed in talking to server to start the job
PEND_JOB_START_UNKNWN, Failed in receiving the reply from server when starting the job
PEND_SBD_NO_MEM, Unable to allocate memory to run job
PEND_SBD_NO_PROCESS, Unable to fork process to run job
PEND_SBD_SOCKETPAIR, Unable to communicate with job process
PEND_SBD_JOB_ACCEPT, Slave batch server failed to accept job
PEND_HOST_LOAD, Load threshold reached
PEND_HOST_QUE_RUSAGE, Queue's requirements for resource reservation not satisfied
PEND_HOST_JOB_RUSAGE, Job's requirements for resource reservation not satisfied
# Added PEND_HOST_JOB_RUSAGE:
PEND_HOST_JOB_RUSAGE, Job requirements for reserving resource (mem) not satisfied
PEND_HOST_JOB_RUSAGE, Job's requirements for reserving resource (sra_submit) not satisfied
PEND_BAD_HOST, Bad host name, host group name or cluster name
PEND_QUEUE_HOST, Host or host group is not used by the queue
PEND_JGRP_JLIMIT, The specified job group has reached its job limit
'''



def run(*args):
  # Run a command and return output
  #sys.stderr.write("Running %s\n" % (' '.join(args)))
  p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  output = p.communicate()[0]
  rc = p.returncode
  if p.returncode:
    sys.stderr.write("Error running: %s: %s: %s\n" % (' '.join(args),rc,output))
    sys.exit(1)
  return output

class Record(object):
  # This is a generic record that I can turn into a dictionary

  def __getitem__(self,key):
    item = getattr(self,key)
    if item is not None: return item

  def __repr__(self):
    text = "%s(" % (self.__class__.__name__)
    for attr in dir(self):
      if attr.startswith('_'): continue
      a = getattr(self,attr)
      if callable(a): continue
      text += "%s=%r," % (attr,a)
    text += ")"
    return text

class QueueRecord(Record):
  def __init__(self):
    self.name = None
    self.hosts = []
    self.hostgroups = []

class HostRecord(Record):
  # Host records have bhosts output

  def __init__(self,text):
    self.host = None
    self.comment = None
    self.state = {}
    self.jobs = {}
    self.parse(text)

  def parse(self,text):
    lines = iter(text.split('\n'))
    while True:
      try:
        line = lines.next()
      except StopIteration:
        break

      if line.startswith("HOST "):
        (toss,self.host) = line.split()

      if line.startswith("STATUS"):
        line = lines.next()
        items = line.split()
        self.state['status'] = items[0]
        self.state['cpuf'] = items[1]
        self.state['jlu'] = items[2]
        self.state['max'] = int(items[3])
        self.state['njobs'] = int(items[4])
        self.state['run'] = int(items[5])
        self.state['ssusp'] = int(items[6])
        self.state['ususp'] = int(items[7])
        self.state['rsv'] = items[8]
        self.state['window'] = items[9]

      if line.startswith(" ADMIN ACTION COMMENT:"):
        (toss,self.comment) = line.split(": ",1)

class JobRecord(Record):
  # Job records have bjobs output

  def __init__(self,line=None):
    self.id = None
    self.reasons = {}
    if line is None: return
    items = line.split()
    if not items: return None
    self.id = int(items[0])
    self.user = items[1]
    self.stat = items[2]
    self.queue = items[3]
    self.from_host = items[4]
    self.exec_host = items[5]
    self.job_name = items[6]
    self.submit_time = " ".join(items[-3:])

class LongJobRecord(JobRecord):

  cpu = None
  cpudelta = None
  time = None

  def parseResourceBlock(self,text):
    rx = re.compile("Requested Resources <(.*?)>,")
    text = text.replace('\n','')
    m = rx.search(text)
    if m:
      return m.groups()[0]
    return ''

  def parseCPU(self,text):
    rx = re.compile("The CPU time used is (\d+) seconds")
    m = rx.search(text)
    if m:
      return int(m.groups()[0])

  def parseReasonBlock(self,text):
    adict = {}
    lines = iter(text.split(";"))

    while True:
      try:
        line = lines.next()
        line.strip()
        details = []
        (reason,hosts) = ('',[])
        if line.find(":") != -1:
          (reason,hosts) = line.split(":",1)
          hosts = hosts.strip('hosts ')
          if hosts.isdigit():
            # bhosts with -l without -p
            hosts = int(hosts)
          else:
            # bhosts with -l -p
            hosts = hosts.replace(' ','')
            hosts = hosts.split(',')
        else:
          reason = line
        if reason:
          adict[reason] = hosts
      except StopIteration:
        break
    return adict

  def parseDetailsBlock(self,data):
    # This sets attributes of this Record class
    rx = re.compile("(.*)<(.*)>")
    items = data.lower().split(',')
    for item in items:
      m = rx.match(item)
      if m:
        setattr(self,m.groups()[0].strip(),m.groups()[1].strip())
        self.id = self.job

  def __init__(self,data):

    job_details_block = ''
    resources_block = ''
    reasons_block = ''

    self.cpu = self.parseCPU(data)
    self.time = time.time()

    lines = iter(data.split("\n"))
    while True:
      try:
        line = lines.next()
        if line.startswith("Job "):
          job_details_block += line.strip()
          while not job_details_block.endswith(">"):
            job_details_block += lines.next()

        if line.find("Submitted") != -1:
          resources_block += line.strip()
          while not resources_block.endswith(';'):
            resources_block += lines.next()

        if line.find("REASONS") != -1:
          reasons_block += lines.next()
          while True:
            line = lines.next()
            if line.find("SCHEDULING") == -1:
              reasons_block += line
            else:
              break

      except StopIteration:
        break

    self.parseDetailsBlock(job_details_block)
    self.resources = self.parseResourceBlock(resources_block)
    self.reasons = self.parseReasonBlock(reasons_block)

class JobsList(list):
  # Extend the list base class to add methods to fetch
  # JobRecords by id.

  def fetchIndex(self,id):
    for job in sorted(self,key=attrgetter('id')):
      if job.id == id:
        return self.index(job)

  def fetch(self,id):
    for job in sorted(self,key=attrgetter('id')):
      if job.id == id:
        return job

class Application(object):
  # This is our application class which parses bhosts and bjobs
  # output and puts info into dictionaries so I can get what I want
  # out of it more easily.

  host_records  = []
  pend_reasons = {}
  pend_reason_defs = {}
  cache = JobsList()

  def loadCache(self):
    if os.path.exists(self.options.cache):
      cachefile = open(self.options.cache)
      self.cache = pickle.load(cachefile)
      cachefile.close()
      self.logger.info("Loaded %s records from cache" % len(self.cache))

  def storeCache(self):
    cachefile = open(self.options.cache,'wb')
    pickle.dump(self.cache,cachefile)
    cachefile.close()

  def updateCache(self,data):
    lastjob = self.cache.fetch(data.id)
    if lastjob:
      if data.cpudelta:
        data.time = time.time()
        idx = self.cache.fetchIndex(data.id)
        self.cache[idx] = data
    else:
      self.cache.append(data)

  def parseReasons(self,text):
    adict = {}
    reasons = text.split("\n")
    reasons = filter(None,reasons)
    for r in reasons:
      adict[r] = []
    return adict

  def getBJobs(self):
    jobs = JobsList()
    # Things we want for each job
    items = ['jobid','stat','user','pendReasons','queue','from_host','exec_host','jobname','command','res_requirements','cpu_used','pend_time']
    condition = 'stat = "pend"'

    sql = 'select ' + ','.join(items) + ' from grid_jobs where ' + condition
    self.cursor.execute(sql)
    for row in self.cursor.fetchall():
      reasons = {}
      J = JobRecord()
      for (k,v) in row.items():
        if k == "pendReasons":
          v = self.parseReasons(v)
        setattr(J,k,v)
      jobs.append(J)

    return jobs

  def parseBHosts(self,data):

    text = ''

    for line in data.split("\n"):
      # A Record is text between HOST lines
      if line.startswith("HOST "):
        # Begin new record, close current record
        if text:
          # Create a Record of text so far
          R = HostRecord(text)
          self.host_records.append(R)
          # reset record
          text = ''
      text += "%s\n" % line

    # The last record
    if text:
      R = HostRecord(text)
      self.host_records.append(R)


  def parseLongBJobs(self,data):
    line_rx = re.compile("^Job <(\d+)>,")
    J = None
    jobs = JobsList()
    text = ''

    lines = iter(data.split("\n"))
    while True:
      try:
        line = lines.next()
      except StopIteration:
        break
      line = line.strip()
      m = line_rx.search(line)
      if m and text:
        # Subsequent matches
        J = LongJobRecord(text)
        if self.cache:
          lastj = self.cache.fetch(J.id)
          if lastj:
            J.time = lastj.time
            if J.cpu is not None and lastj.cpu is not None:
              J.cpudelta = J.cpu - lastj.cpu
        self.updateCache(J)
        jobs.append(J)
        text = "%s\n" % line
      elif m:
        text = "%s\n" % line
      elif line and text:
        text += "%s\n" % line

    # The last record before end of output...
    if text:
      J = LongJobRecord(text)
      if self.cache:
        lastj = self.cache.fetch(J.id)
        if lastj:
          J.time = lastj.time
          if J.cpu is not None and lastj.cpu is not None:
            J.cpudelta = J.cpu - lastj.cpu
      self.updateCache(J)
      jobs.append(J)

    return jobs

  def parseWideBJobs(self,data):
    line_rx = re.compile("^(\d+) ")
    J = None
    jobs = []

    lines = iter(data.split("\n"))
    while True:
      try:
        line = lines.next()
      except StopIteration:
        break

      if not line: continue
      if line.startswith("JOBID"): continue
      if line.startswith("No pending job"): return

      m = line_rx.search(line)
      if m and J:
        jobs.append(J)
        id = m.groups()[0]
        J = JobRecord(line)
        J.id = id
      elif m:
        id = m.groups()[0]
        J = JobRecord(line)
        J.id = id
      else:
        hosts = None
        line = line.lstrip()
        line = line.replace(';','')
        if line.find(':') != -1:
          (line,hosts) = line.split(':')
          hosts = int(hosts.strip("hosts "))
        if J and line not in J.reasons:
          J.reasons[line] = hosts

    # The last record before end of output...
    if J: jobs.append(J)
    return jobs

  def parseHostGroups(self):
    # Determine host group membership.
    # Done after list of queues is determined.
    self.hostgroups = {}
    R = None
    trigger = False

    for queue in self.queues:
      for hostgroup in queue.hostgroups:

        if hostgroup in self.hostgroups:
          # already seen this group, add to queue
          queue.hosts.extend(self.hostgroups[hostgroup])
          continue

        args = ["bhosts","-w",hostgroup]
        output = run(*args)
        lines = iter(output.split("\n"))
        while True:
          try:
            line = lines.next()
          except StopIteration:
            break

          line = line.strip()
          if not line: continue
          if line.startswith("HOST_NAME"): continue
          host = line.split()[0]
          if host not in queue.hosts:
            queue.hosts.append(host)
            # this acts as a cache so we don't rerun bhosts
            if hostgroup not in self.hostgroups:
              self.hostgroups[hostgroup] = []
            self.hostgroups[hostgroup].append(host)

  def parseBQueues(self):
    # Get list of queues and what host groups they use
    self.queues = []

    R = None
    queue = None
    hosts = None
    trigger = False

    args = ["bqueues","-l"]
    output = run(*args)
    lines = iter(output.split("\n"))

    while True:
      try:
        line = lines.next()
      except StopIteration:
        break

      line = line.strip()
      if not line: continue
      if line.startswith("QUEUE"):
        (toss,name) = line.split(": ")
        R = QueueRecord()
        R.name = name
      if line.startswith("HOSTS"):
        (toss,hosts) = line.split(": ")
        hosts = hosts.replace('/','')
        R.hostgroups = hosts.split()
        self.queues.append(R)

  def closed_AdmReport(self):
    # This reports closed_Adm info

    count = 0
    t_max = 0
    r_max = 0
    n_max = 0

    for Host in self.host_records:
      if Host.state['status'] == 'closed_Adm':
        count += 1
        n_cpu = None

        output = run("bjobs","-l","-u","all","-m",Host.host)
        Host.jobs = self.parseLongBJobs(output)

        t_max += Host.state['max']
        r_max += Host.state['run']
        n_max += Host.state['njobs']

        for job in Host.jobs:
          if job.cpudelta > 0 and n_cpu is None:
            n_cpu = 1
          elif job.cpudelta > 0:
            n_cpu += 1
          elif job.cpudelta == 0:
            n_cpu = 0

        print "%s: max %s: njobs %s: run %s: cpu %s: comment %s" % (Host.host,Host.state['max'],Host.state['njobs'],Host.state['run'],n_cpu,Host.comment)

        if self.options.verbose:
          for job in Host.jobs:
            pp.pprint(job.__dict__)

    print "%s hosts, %s slots, %s njobs, %s running" % (count,t_max,n_max,r_max)

  def parseArgs(self):
    usage = """%prog [options]"""

    optParser = OptionParser(usage)
    optParser.add_option(
      "-l","--loglevel",
      type="choice",
      choices=["CRITICAL","ERROR","WARNING","INFO","DEBUG"],
      dest="loglevel",
      help="set the log level",
      default="INFO",
    )
    optParser.add_option(
      "--syslog",
      action="store_true",
      dest="use_syslog",
      help="Use syslog",
      default=False,
    )
    optParser.add_option(
      "--verbose",
      action="store_true",
      dest="verbose",
      help="Long output",
      default=False,
    )
    optParser.add_option(
      "--host_group",
      action="store",
      dest="host_group",
      help="Specify host group",
      default=None,
    )
    optParser.add_option(
      "--hosts",
      action="store_true",
      dest="hosts",
      help="Run hosts check",
      default=False,
    )
    optParser.add_option(
      "--cache",
      action="store",
      dest="cache",
      help="Specify cache file (optional)",
      default="lsftool.cache",
    )
    # FIXME: remove?
    optParser.add_option(
      "--maxage",
      action="store",
      dest="maxage",
      help="Cache job data for N seconds",
      default=86400,
    )
    optParser.add_option(
      "--jobs",
      action="store_true",
      dest="jobs",
      help="Run jobs check",
      default=False,
    )
    optParser.add_option(
      "--queue",
      action="store",
      dest="queue",
      help="Specify queue",
      default=None,
    )
    optParser.add_option(
      "--jobid",
      action="store",
      dest="jobid",
      help="Specify job ID",
      default=None,
    )
    optParser.add_option(
      "-v","--version",
      action="store_true",
      dest="version",
      help="Display version",
      default=False,
    )
    (self.options, self.args) = optParser.parse_args()

  def _getQueue(self,name):
    for x in self.queues:
      if x.name == name:
        return x
    raise Exception("Queue '%s' not found" % name)

  def jobsReport(self,jobs):

    # Sorted by queue name...
    sys.stderr.write("Analyzing %s job(s)\n" % len(jobs))
    for job in jobs:
      if job.status != "pend":
        sys.stderr.write("Job '%s' is in state '%s'\n" % (job.id,job.status))
        continue

      queue = self._getQueue(job.queue)
      if self.options.verbose:
        sys.stderr.write("job %s is in queue %s having %s hosts\n" % (job.id,job.queue,len(queue.hosts)))

      qhosts = copy.copy(queue.hosts)
      for reason,jhosts in sorted(job.reasons.items(), key=lambda e: len( e[1] ), reverse=True):
        count = 0
        for host in jhosts:
          if host in qhosts:
            qhosts.remove(host)
            count += 1

        if count or len(jhosts) == 0:
          reason = self.pend_reason_defs[reason]
          if reason not in self.pend_reasons:
            self.pend_reasons[reason] = 1
          else:
            self.pend_reasons[reason] += 1

        if self.options.verbose:
          if len(jhosts) == 0:
            sys.stderr.write("Because '%s', this job is pending\n" % (reason))
          else:
            sys.stderr.write("Because '%s', %s hosts are unavailable\n" % (reason,len(qhosts)))
            sys.stderr.write("%s less hosts for me, %s hosts left meet requirements\n" % (count,len(qhosts)))

        if len(qhosts) == 0:
          break

    for reason,value in self.pend_reasons.items():
      print "%s %s" % (reason,value)

  def parseReasonDefs(self):
    for line in pending_reasons_txt.split("\n"):
      line = line.strip()
      if line.startswith("#"): continue
      if line.find(',') != -1:
        (reason,text) = line.split(',',1)
        text = text.strip()
        reason = reason.strip()
        self.pend_reason_defs[text] = reason

  def fatal(self,text):
    self.logger.fatal("%s", text)
    sys.exit(1)

  def prepareLogger(self):
    """prepares a logger optionally to use syslog and with a log level"""
    (use_syslog,loglevel) = (self.options.use_syslog,self.options.loglevel)

    logger = logging.getLogger("lsftool")
    if use_syslog:
      handler = logging.handlers.SysLogHandler(address="/dev/log")
    else:
      handler = logging.StreamHandler()

    datefmt = "%b %d %H:%M:%S"
    fmt = "%(asctime)s %(name)s[%(process)d]: %(levelname)s: %(message)s"
    fmtr = logging.Formatter(fmt,datefmt)
    handler.setFormatter(fmtr)
    logger.handlers = []
    logger.addHandler(handler)
    logger.setLevel(logging._levelNames[loglevel])
    self.logger = logger

  def main(self):

    self.parseArgs()
    self.prepareLogger()
    self.parseReasonDefs()

    if self.options.version:
      print "%s %s" % (name,version)
      return

    self.loadCache()

    # Get list of active queues first
    self.parseBQueues()

    # Get expand queue records with host members
    self.parseHostGroups()

    # We need -l long output to get action comments
    args = ["bhosts","-l"]
    if self.options.host_group is not None:
      args.append(self.options.host_group)
    output = run(*args)
    self.parseBHosts(output)

    # Long form output, includes resources and reasons
    args = ["bjobs","-l","-u","all","-p"]
    if self.options.host_group is not None:
      args.extend(["-m",self.options.host_group])
    if self.options.queue is not None:
      args.extend(["-q",self.options.queue])
    if self.options.jobid is not None:
      args.append(self.options.jobid)
    output = run(*args)
    jobs = self.parseLongBJobs(output)

    if self.options.hosts:
      self.closed_AdmReport()
    elif self.options.jobs:
      if jobs:
        self.jobsReport(jobs)
      else:
        print "no jobs found"

    self.storeCache()

if __name__ == "__main__":
  A = Application()
  try:
    A.main()
  except KeyboardInterrupt:
    sys.exit()

