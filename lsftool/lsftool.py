#! /usr/bin/python
#
# This feels like too much code for such a simple job.  But I'm finding
# it much easier to parse bhosts and bjobs output and ask for exactly
# what I'm interested in, rather than reading that output directly
# or using some shell, sed, awk, etc.
#

import copy
import hashlib
import time
import subprocess
from optparse import OptionParser,OptionValueError
from operator import itemgetter,attrgetter
import pprint
import sys
import os
import re

rrdAvailable = True

try:
  from pyrrd.rrd import DS,RRA,RRD
except Exception:
  rrdAvailable = False

name = "lsftool"
version = "0.5.2"

pp = pprint.PrettyPrinter(indent=4)
job_rx = re.compile("^(\d+) ")

def run(*args):
  # Run a command and return output
  #print "Running %s" % (' '.join(args))
  p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
  output = p.communicate()[0]
  rc = p.returncode
  if p.returncode:
    print "Error running: %s: %s: %s" % (' '.join(args),rc,output)
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

  def parseResourceBlock(self,text):
    rx = re.compile("Requested Resources <(.*?)>,")
    text = text.replace('\n','')
    m = rx.search(text)
    if m:
      return m.groups()[0]
    return ''

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

class Application(object):
  # This is our application class which parses bhosts and bjobs
  # output and puts info into dictionaries so I can get what I want
  # out of it more easily.

  host_records  = []
  pend_reasons = {}

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
    jobs = []
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
        jobs.append(J)
        #id = m.groups()[0]
        text = "%s\n" % line
      elif m:
        # First match
        #id = m.groups()[0]
        text = "%s\n" % line
      elif line and text:
        text += "%s\n" % line

    # The last record before end of output...
    if text:
      J = LongJobRecord(text)
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
        # Get job info for this host
        output = run("bjobs","-w","-u","all","-m",Host.host)
        Host.jobs = self.parseWideBJobs(output)

        t_max += Host.state['max']
        r_max += Host.state['run']
        n_max += Host.state['njobs']

        if self.options.verbose:
          #print "%s %s" % (Host.host,Host.state['status'])
          print "%s: %s max: %s njobs: %s run: %s" % (Host.host,Host.state['max'],Host.state['njobs'],Host.state['run'],Host.comment)
          for job in Host.jobs:
            pp.pprint(job.__dict__)
        else:
          print "%s: %s max: %s njobs: %s run: %s" % (Host.host,Host.state['max'],Host.state['njobs'],Host.state['run'],Host.comment)

    print "%s hosts, %s slots, %s njobs, %s running" % (count,t_max,n_max,r_max)

  def parseArgs(self):
    usage = """%prog [options]"""

    optParser = OptionParser(usage)
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
      "--jobs",
      action="store_true",
      dest="jobs",
      help="Run jobs check",
      default=False,
    )
    optParser.add_option(
      "--pending",
      action="store_true",
      dest="pending",
      help="Check pending jobs only",
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
      "--rrd",
      action="store_true",
      dest="rrd",
      help="Save data to rrd",
      default=False,
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

  def createRRD(self,rrdfile):
    dss = []
    rras = []
    ds1 = DS(dsName='jobs', dsType='GAUGE', heartbeat=300, minval=0, maxval='U')
    dss.append(ds1)

    rra0 = RRA(cf='AVERAGE', xff=0.5, steps=1, rows=288) # 1 day
    rra1 = RRA(cf='AVERAGE', xff=0.5, steps=6, rows=48) # 1 day
    rras.extend([rra0,rra1])

    # start Thu Oct  7 10:13:48 CDT 2010 - 1 week
    starttime = time.time()
    myRRD = RRD(rrdfile, ds=dss, rra=rras, start=starttime)
    myRRD.create()

  def updateRRD(self,reason,value):

    digest = hashlib.md5(reason).hexdigest()
    # FIXME: set full path
    rrdfile = "%s.rrd" % digest
    if not os.path.exists(rrdfile):
      self.createRRD(rrdfile)
    myRRD = RRD(rrdfile)
    myRRD.bufferValue(int(time.time()), value)
    myRRD.update()

  def jobsReport(self,jobs):

    # Sorted by queue name...
    print "Analyzing %s job(s)" % len(jobs)
    for job in jobs:
      if job.status != "pend":
        reason = "job is in state '%s'"
        job.reasons["Job is in state '%s'" % (job.status)] = []

      try:
        queue = self._getQueue(job.queue)
        if self.options.verbose:
          print "job %s is in queue %s having %s hosts" % (job.id,job.queue,len(queue.hosts))

        qhosts = copy.copy(queue.hosts)
        for reason,jhosts in sorted(job.reasons.items(), key=lambda e: len( e[1] ), reverse=True):
          count = 0
          for host in jhosts:
            if host in qhosts:
              qhosts.remove(host)
              count += 1

          if count or len(jhosts) == 0:
            if reason not in self.pend_reasons:
              self.pend_reasons[reason] = 1
            else:
              self.pend_reasons[reason] += 1

          if self.options.verbose:
            if len(jhosts) == 0:
              print 'Because "%s", this job is pending' % (reason)
            else:
              print 'Because "%s", %s hosts are unavailable' % (reason,len(qhosts))
              print "%s less hosts for me, %s hosts left meet requirements" % (count,len(qhosts))

          if len(qhosts) == 0:
            break

      except Exception, details:
        print "Error parsing job: %r: %r" % (job,details)
      # end of function

    for reason,value in self.pend_reasons.items():
      print "%s %s" % (reason,value)

      if self.options.rrd and rrdAvailable:
        self.updateRRD(reason,value)

  def main(self):

    self.parseArgs()

    if self.options.version:
      print "%s %s" % (name,version)
      return

    # Get list of active queues first
    self.parseBQueues()

    # Get expand queue records with host members
    self.parseHostGroups()

    if self.options.hosts:
      # We need -l long output to get action comments
      args = ["bhosts","-l"]
      if self.options.host_group is not None:
        args.append(self.options.host_group)
      output = run(*args)
      self.parseBHosts(output)
      self.closed_AdmReport()
      return

    if self.options.jobs:
      # Long form output, includes resources and reasons
      args = ["bjobs","-l","-u","all","-p"]
      if self.options.pending:
        args.append("-p")
      if self.options.host_group is not None:
        args.extend(["-m",self.options.host_group])
      if self.options.queue is not None:
        args.extend(["-q",self.options.queue])
      if self.options.jobid is not None:
        args.append(self.options.jobid)
      output = run(*args)
      # We return a list here because it's also used in
      # parseBHosts() in this way.
      jobs = self.parseLongBJobs(output)
      if jobs:
        self.jobsReport(jobs)
      else:
        print "no jobs found"
      return

if __name__ == "__main__":
  A = Application()
  try:
    A.main()
  except KeyboardInterrupt:
    sys.exit()

