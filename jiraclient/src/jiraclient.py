#!/usr/bin/python
#
# jiraclient.py
#
# A Python Jira XML-RPC/SOAP Client
#
# (C) 2007,2008,2009,2010: Matthew Callaway
#
# jiraclient is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2, or (at your option) any later version.
#
# jiraclient.py is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
# details.
#
# You may have received a copy of the GNU General Public License along with
# jiraclient.py.  If not, write to the Free Software Foundation, Inc., 59
# Temple Place - Suite 330, Boston, MA 02111-1307, USA.

import os
import re
import sys
import time
import logging, logging.handlers
from stat import *
from optparse import OptionParser,OptionValueError
import ConfigParser
import xmlrpclib
import SOAPpy
import types

time_rx = re.compile('^\d+[mhdw]')
time_t_rx = re.compile('\s+%(\d+[mhdw])%')

def parse_time(line):
  def repl(m): return ''
  time = None
  m = time_t_rx.search(line)
  if m:
    time = m.group(1)
    line = time_t_rx.sub(repl,line)
  return (time,line)

def inspect(obj,padding=None):
  # Traverse an object printing non-private attributes
  if padding is None:
    padding = 5
  if type(obj) is types.StringType:
    print "%s%s" % (' ' * padding,obj)
  elif type(obj) is types.NoneType:
    print "%s%s" % (' ' * padding,'None')
  else:
    for attr in dir(obj):
      if attr.startswith('_'): continue
      a = getattr(obj,attr)
      if callable(a): continue
      if a.__class__ is SOAPpy.Types.structType:
        inspect(a,padding+5)
      if a.__class__ is SOAPpy.Types.typedArrayType:
        print "%s%s:" % (' ' * padding, attr)
        for x in a:
          inspect(x,padding+5)
      else:
        print "%s%s: %s" % (' ' * padding,attr,a)

class Issue(object):
  # This Issue class exists so that we can easily convert an
  # issue instance into a dictionary later.
  def __init__(self,summary=None):
    if summary is not None:
      self.summary = summary

  def __getitem__(self,key):
    item = getattr(self,key)
    if item is not None: return item

class Jiraclient(object):

  version = "1.5.2"

  priorities = {}
  typemap = {}

  def fatal(self,msg=None):
    self.logger.fatal(msg)
    sys.exit(1)

  def print_version(self):
    print "jiraclient version %s" % self.version

  def parse_args(self):
    usage = """%prog [options]

 Sample Usage:
  - Standard issue creation in project named INFOSYS:
    jiraclient.py -u 'username' -p 'jirapassword' -A 'matt callaway' -P INFOSYS -T task -S 'Do some task'

 - Get numerical Version IDs for Project named INFOSYS:
   jiraclient.py -u 'username' -p 'jirapassword' -a getVersions INFOSYS

 - Get numerical Component IDs for Project named INFOSYS:
   jiraclient.py -u 'username' -p 'jirapassword' -a getComponents INFOSYS

 - Create an issue with a specified Component and Fix Version 
   and assign it to myself:
   jiraclient.py -u 'username' -p 'jirapassword' -A 'username' -P INFOSYS -Q major -F 10000  -C 10003 -T epic -S 'Investigate Platform IFS'
"""
    optParser = OptionParser(usage)
    optParser.add_option(
      "--config",
      action="store",
      dest="config",
      help="Read configuration from this file",
      default=os.path.join(os.environ["HOME"],'.jiraclientrc')
    )
    optParser.add_option(
      "-a","--api",
      action="store",
      dest="api",
      help="Call this API method",
      default=None,
    )
    optParser.add_option(
      "-c","--comment",
      action="store",
      dest="comment",
      help="Comment text",
      default=None,
    )
    optParser.add_option(
      "-l","--loglevel",
      type="choice",
      choices=["CRITICAL","ERROR","WARNING","INFO","DEBUG"],
      dest="loglevel",
      help="Set the log level",
      default="INFO",
    )
    optParser.add_option(
      "--link",
      action="store",
      dest="link",
      help="Link two issues",
      default=None,
    )
    optParser.add_option(
      "--unlink",
      action="store",
      dest="unlink",
      help="Unlink two issues",
      default=None,
    )
    optParser.add_option(
      "--subtask",
      action="store",
      dest="subtask",
      help="Make issue into a sub-task of another",
      default=None,
    )
    optParser.add_option(
      "--template",
      action="store",
      dest="template",
      help="Make a set of Issues based on a YAML template file",
      default=None,
    )
    optParser.add_option(
      "-n","--noop",
      action="store_true",
      dest="noop",
      help="Parse bug file but don't connect to Jira",
      default=False,
    )
    optParser.add_option(
      "-u","--user",
      action="store",
      dest="user",
      help="Jira user",
      default=None,
    )
    optParser.add_option(
      "-p","--password",
      action="store",
      dest="password",
      help="Jira password",
      default=None,
    )
    optParser.add_option(
      "-d","--display",
      action="store_true",
      dest="display",
      help="Display an existing given Jira issue ID",
      default=False,
    )
    optParser.add_option(
      "-i","--issue",
      action="store",
      dest="issueID",
      help="Jira issue ID (to modify)",
      default=None,
    )
    optParser.add_option(
      "-r","--remaining",
      action="store",
      dest="remaining",
      help="Jira issue time 'remaining estimate'",
      default=None,
    )
    optParser.add_option(
      "-t","--time",
      action="store",
      dest="timetracking",
      help="Jira issue time 'original estimate'",
      default=None,
    )
    optParser.add_option(
      "-A","--assignee",
      action="store",
      dest="assignee",
      help="Jira assignee",
      default=None,
    )
    optParser.add_option(
      "-C","--components",
      action="store",
      dest="components",
      help="Jira project components, comma separated list",
      default=None,
    )
    optParser.add_option(
      "-D","--description",
      action="store",
      dest="description",
      help="Jira issue description text",
      default=None,
    )
    optParser.add_option(
      "-E","--environment",
      action="store",
      dest="environment",
      help="Jira environment",
      default=None,
    )
    optParser.add_option(
      "-F","--fixversions",
      action="store",
      dest="fixversions",
      help="Jira project 'fix versions', comma separated list",
      default=None,
    )
    optParser.add_option(
      "-P","--project",
      action="store",
      dest="project",
      help="Jira project",
      default=None,
    )
    optParser.add_option(
      "-Q","--priority",
      action="store",
      dest="priority",
      help="Issue priority name",
      default=None,
    )
    optParser.add_option(
      "-S","--summary",
      action="store",
      dest="summary",
      help="Issue summary",
      default=None,
    )
    optParser.add_option(
      "-T","--type",
      action="store",
      dest="type",
      help="Issue type",
      default=None,
    )
    optParser.add_option(
      "-U","--jiraurl",
      action="store",
      dest="jiraurl",
      help="The Jira URL",
      default=None,
    )
    optParser.add_option(
      "-V","--affecstversions",
      action="store",
      dest="affectsversions",
      help="Jira project 'affects versions', comma separated list",
      default=None,
    )
    optParser.add_option(
      "--syslog",
      action="store_true",
      dest="use_syslog",
      help="Use syslog",
      default=False,
    )
    optParser.add_option(
      "-v","--version",
      action="store_true",
      dest="version",
      help="Version information",
      default=False,
    )
    (self.options, self.args) = optParser.parse_args()

  def prepare_logger(self):
    """prepares a logger optionally to use syslog and with a log level"""
    (use_syslog,loglevel) = (self.options.use_syslog,self.options.loglevel)

    logger = logging.getLogger("jiraclient")
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

  def read_config(self):

    parser = ConfigParser.ConfigParser()

    if self.options.config is not None:
      stat = os.stat(self.options.config)
      if S_IMODE(os.stat(self.options.config).st_mode) != int("600",8):
        self.logger.warning("Config file %s is not mode 600" % (self.options.config))
      try:
        parser.readfp(file(self.options.config,'r'))
      except IOError, details:
        # No file is ok, just return
        return
      except ConfigParser.ParsingError:
        self.logger.warning("Body has multiple lines, truncating...")
      except Exception, details:
        self.fatal("Unable to parse file at %r: %s" % (self.options.config,details))

    for (k,v) in (parser.items('jiraclient')):
      if not hasattr(self.options,k) or getattr(self.options,k) is None:
        setattr(self.options,k,v)

    # Map the items in the rc file to options, but only for issue *creation*
    if self.options.issueID is None:
      for (k,v) in (parser.items('issues')):
        if not hasattr(self.options,k) or getattr(self.options,k) is None:
          setattr(self.options,k,v)

  def get_project_id(self,project):

    auth = self.proxy.login(self.options.user,self.options.password)
    result = self.proxy.getProjectsNoSchemes(auth)

    if result.__class__ is SOAPpy.Types.typedArrayType:
      for item in result:
        if hasattr(item,'key') and getattr(item,'key') == project:
          return item['id']
    else:
      for hash in result:
        if hash.has_key('key') and hash['key'] == project:
          return hash['id']

  def set_issue_types(self,projectID):

    auth = self.proxy.login(self.options.user,self.options.password)
    result = self.proxy.getIssueTypesForProject(auth,projectID)
    for item in result:
      self.typemap[item['name'].lower()] = item['id']
    result = self.proxy.getSubTaskIssueTypesForProject(auth,projectID)
    for item in result:
      self.typemap[item['name'].lower()] = item['id']

  def get_priorities(self):
    auth = self.proxy.login(self.options.user,self.options.password)
    result = self.proxy.getPriorities(auth)
    for item in result:
      self.priorities[item['name'].lower()] = item['id']

  def create_issue_obj(self):
    # Creates an Issue object based on CLI args and config file.
    # We do this for create and modify operations.

    parser = ConfigParser.ConfigParser()
    issue = Issue()

    attrs = {
      'project'         : True,
      'type'            : True,
      'summary'         : True,
      'assignee'        : False,
      'components'      : False,
      'fixversions'     : False,
      'affectsversions' : False,
      'priority'        : False,
      'environment'     : False,
      'timetracking'    : False,
    }

    for (k,v) in attrs.items():
      if hasattr(self.options,k) and getattr(self.options,k) is not None:
        setattr(issue,k,getattr(self.options,k))
      else:
        if self.options.issueID is None:
          # This is a create, which requires some attrs
          if v is True:
            self.fatal("You must specify: %s" % k)

    # Timetracking is only allowed in update
    if self.options.issueID is None and hasattr(issue,'timetracking'):
      time = getattr(issue,'timetracking')
      m = time_rx.match(time)
      if not m:
        self.fatal("Time estimate has dubious format: %s" % (time))
      self.fatal("The timetracking option -t is only valid in 'modify' operations, not 'create'")

    # Now that we have the project, get its ID and then project types
    if hasattr(issue,'project'):
      projectID = self.get_project_id(issue.project)
      if not projectID and self.options.issueID is None:
        self.fatal("Project %s is unknown" % issue.project)
      self.set_issue_types(projectID)

    # A given type must be known to Jira, convert to numerical form
    if hasattr(issue,'type'):
      if issue.type not in self.typemap:
        print "Known issue types:\n%r\n" % self.typemap
        self.fatal("Unknown issue type: '%s' for Project: '%s'" % (issue.type,issue.project))
      issue.type = self.typemap[issue.type]

    # Handle various things...
    if hasattr(issue,'components'):
      issue.components = [{'id':x} for x in issue.components.split(',')]

    if hasattr(issue,'fixversions'):
      issue.fixVersions = [{'id':x} for x in issue.fixversions.split(',')]
      del issue.fixversions

    if hasattr(issue,'affectsversions'):
      issue.affectsVersions = [{'id':x} for x in issue.affectsVersions.split(',')]
      del issue.affectsversions

    if hasattr(issue,'priority'):
      issue.priority = self.priorities[issue.priority.lower()]

    return issue

  def get_issue(self,issueID):
    auth = self.proxy.login(self.options.user,self.options.password)
    result = self.proxy.getIssue(auth,issueID)
    return result

  def get_issue_links(self,issueID,type=None):
    if self.proxy.__class__ is not SOAPpy.WSDL.Proxy:
      self.fatal("Only the SOAP client can link issues")
    auth = self.proxy.login(self.options.user,self.options.password)
    result = self.proxy.getIssue(auth,issueID)
    result = self.proxy.getLinkedIssues(auth,SOAPpy.Types.longType(long(result['id'])),'')
    return result

  def add_comment(self,issueID,comment):
    auth = self.proxy.login(self.options.user,self.options.password)
    result = self.proxy.addComment(auth,issueID,comment)
    print "Modified %s/browse/%s" % \
     (self.proxy.getServerInfo(auth)['baseUrl'], issueID)

  def update_estimate(self,estimate,issueID):
    if self.proxy.__class__ is not SOAPpy.WSDL.Proxy:
      self.logger.error("Only the SOAP interface supports this operation")
      return

    m = time_rx.match(estimate)
    if not m:
      self.logger.warning("Time estimate has dubious format: %s: no action taken" % (estimate))
      return

    # Note timeSpent must be set, and cannot be less than 1m
    dt_today = SOAPpy.dateTimeType(time.gmtime(time.time())[:6])
    worklog = {'startDate':dt_today,'timeSpent':'1m','comment':'jiraclient updates remaining estimate to %s' % estimate}
    if self.options.noop:
      self.logger.info("Would update time remaining: %s: %s" % (issueID,estimate))
      return
    self.logger.info("Update time remaining: %s: %s" % (issueID,estimate))
    auth = self.proxy.login(self.options.user,self.options.password)
    self.proxy.addWorklogWithNewRemainingEstimate(auth, issueID, worklog, estimate)

  def modify_issue(self,issueID,issue):

    issue = issue.__dict__
    auth = self.proxy.login(self.options.user,self.options.password)

    if self.proxy.__class__ is SOAPpy.WSDL.Proxy:
      # SOAP takes a list of dictionaries of parameters, we need to convert to the right format
      paramlist = []

      for item in issue:
        params = {'id':None,'values':None}
        if item == 'type':
          params['id'] = 'issuetype' # type becomes issuetype? WTF?
        else:
          params['id'] = item
        if type(issue[item]) is list:
          params['values'] = [x.values()[0] for x in issue[item]]
        else:
          params['values'] = issue[item]
        if params not in paramlist:
          paramlist.append(params)
      issue = paramlist

    print issue
    if self.options.noop: return
    result = self.proxy.updateIssue(auth,issueID,issue)

    print "Modified %s/browse/%s" % \
     (self.proxy.getServerInfo(auth)['baseUrl'], issueID)

  def link_issues(self,issueFrom,linkType,issueTo):
    if self.options.noop: return
    if self.proxy.__class__ is not SOAPpy.WSDL.Proxy:
      self.fatal("Only the SOAP client can link issues")
    auth = self.proxy.login(self.options.user,self.options.password)
    fromIssue = self.proxy.getIssue(auth,issueFrom)
    fromId = SOAPpy.Types.longType(long(fromIssue['id']))
    toIssue = self.proxy.getIssue(auth,issueTo)
    toId = SOAPpy.Types.longType(long(toIssue['id']))
    result = self.proxy.linkIssue(auth,fromId,toId,linkType,True,False)
    return result

  def unlink_issues(self,issueFrom,linkType,issueTo):
    if self.options.noop: return
    if self.proxy.__class__ is not SOAPpy.WSDL.Proxy:
      self.fatal("Only the SOAP client can link issues")
    auth = self.proxy.login(self.options.user,self.options.password)
    fromIssue = self.proxy.getIssue(auth,issueFrom)
    fromId = SOAPpy.Types.longType(long(fromIssue['id']))
    toIssue = self.proxy.getIssue(auth,issueTo)
    toId = SOAPpy.Types.longType(long(toIssue['id']))
    result = self.proxy.unlinkIssue(auth,fromId,toId,linkType)
    return result

  def subtask_link(self,parent,child):
    if self.options.noop: return
    if self.proxy.__class__ is not SOAPpy.WSDL.Proxy:
      self.fatal("Only the SOAP client can link issues")
    auth = self.proxy.login(self.options.user,self.options.password)
    parent = self.proxy.getIssue(auth,parent)
    parentId = SOAPpy.Types.longType(long(parent['id']))
    child = self.proxy.getIssue(auth,child)
    childId = SOAPpy.Types.longType(long(child['id']))

    # issueType is always jira_subtask_link, which we get from the Jira DB:
    # mysql> select * from issuelinktype;
    # +-------+-------------------+---------------------+----------------------+--------------+
    # | ID    | LINKNAME          | INWARD              | OUTWARD              | pstyle       |
    # +-------+-------------------+---------------------+----------------------+--------------+
    # | 10010 | Duplicate         | is duplicated by    | duplicates           | NULL         | 
    # | 10000 | jira_subtask_link | jira_subtask_inward | jira_subtask_outward | jira_subtask | 
    # | 10011 | Depends           | is depended on by   | depends on           | NULL         | 
    # | 10012 | Blocks            | is blocked by       | blocks               | NULL         | 
    # +-------+-------------------+---------------------+----------------------+--------------+
    # 4 rows in set (0.00 sec)
    linkType = SOAPpy.Types.longType(long(10000))

    # If we don't already know issue types, figure them out...
    projectID = self.get_project_id(child.project)
    if not projectID:
      self.fatal("Project %s is unknown" % child.project)
    self.set_issue_types(projectID)

    # Set sub-task link
    result = self.proxy.createSubtaskLink(auth,parentId,childId,linkType)

    # Set issue type to sub-task after linking.
    issue = Issue()
    issue.type = self.typemap['sub-task']
    issue.project = projectID
    self.modify_issue(child.key,issue)

    return result

  def create_issue(self,issue):

    issue = issue.__dict__
    print issue
    if self.options.noop:
      # return a fake Issue Key
      return 'NOPROJECT-0'
    auth = self.proxy.login(self.options.user,self.options.password)
    newissue = self.proxy.createIssue(auth,issue)
    issueID = newissue["key"]
    print "Created %s/browse/%s" % \
     (self.proxy.getServerInfo(auth)['baseUrl'], issueID)

    return issueID

  def create_issues_from_template(self):

    if self.proxy.__class__ is not SOAPpy.WSDL.Proxy:
      self.fatal("Only the SOAP extended webservice supports issue templates")

    if not hasattr(self.options,'epic_theme'):
      self.fatal("Configuration lacking epic_theme parameter")

    import yaml

    if not os.path.exists(self.options.template):
      self.fatal("No such file: %s" % self.options.template)

    template = yaml.load(file(self.options.template,"r"))

    if not template.has_key('project'):
      self.fatal("Template has no 'project' key")

    auth = self.proxy.login(self.options.user,self.options.password)

    # Project ID determines available Issue types.
    project = template['project']
    projectID = self.get_project_id(template['project'])
    del template['project']

    # Issue types must include epic, story and subtask
    self.set_issue_types(projectID)
    for item in ['epic','story','sub-task']:
      if not self.typemap.has_key(item):
        self.fatal("Project '%s' does not have required issue type '%s'" % (projectID, item))

    for epic,stories in template.items():
      e = Issue(epic)
      e.project = project
      e.type = self.typemap['epic']
      eid = None
      if not self.options.noop:
        eid = self.create_issue(e)
        # set epic/theme of eid
        e.customFieldValues = [{'values':eid,'customfieldId':self.options.epic_theme}]
        self.modify_issue(eid,e)
      else:
        print e.__dict__

      if stories:
        for story in stories:
          subtasks = None
          if type(story) is not types.StringType:
            for story,subtasks in story.items():

              if type(story) is not types.StringType:
                self.fatal("Template format error: illegal nested entry '%r'" % (story))
          s = Issue(story)
          s.project = project
          s.type = self.typemap['story']
          (time,s.summary) = parse_time(s.summary)
          if eid:
            s.customFieldValues = [{'values':eid,'customfieldId':self.options.epic_theme}]
          if self.options.noop:
            print s.__dict__
          else:
            sid = self.create_issue(s)
            s = Issue()
            if time is not None:
              s.timetracking = time
              self.modify_issue(sid,s)

          if subtasks:
            for subtask in subtasks:
              if type(subtask) is not types.StringType:
                self.fatal("Template format error: illegal nested entry '%r'" % (subtask))
              st = Issue(subtask)
              # You cannot directly create a sub-task, you have to
              # create an issue, set sub-task link, then set type = sub-task
              st.project = project
              st.type = self.typemap['story']
              (time,st.summary) = parse_time(st.summary)
              st.customFieldValues = [{'values':eid,'customfieldId':self.options.epic_theme}]
              if self.options.noop:
                print st.__dict__
              else:
                stid = self.create_issue(st)
                st = Issue()
                if time is not None:
                  st.timetracking = time
                  self.modify_issue(stid,st)
                # This converts to a sub-task
                self.subtask_link(sid,stid)

    if not self.options.noop:
      print "Issue Filter: %s/secure/IssueNavigator.jspa?reset=true&jqlQuery=cf[%s]+%%3D+%s+ORDER+BY+issuetype+ASC" % (self.proxy.getServerInfo(auth)['baseUrl'],self.options.epic_theme.replace('customfield_',''),eid)

  def call_API(self,api,args):
    auth = self.proxy.login(self.options.user,self.options.password)
    func = getattr(self.proxy,api)
    args = ' '.join(args)
    if args:
      result = func(auth,args)
    else:
      result = func(auth)

    if self.proxy.__class__ is SOAPpy.WSDL.Proxy:
      for item in result:
        inspect(item)

    else:
      print result

      for item in result:
        if type(item) is dict:
          for (k,v) in item.items():
            print "%s = %s" % (k,v)
          print
        else:
          print result

  def run(self):

    self.parse_args()

    if self.options.version:
      self.print_version()
      return

    self.prepare_logger()
    self.read_config()

    if self.options.user is None:
      self.fatal("Please specify Jira user")

    if self.options.password is None:
      self.fatal("Please specify Jira password")

    if self.options.jiraurl is None:
      self.fatal("Please specify the Jira URL")

    if self.options.jiraurl.lower().find('soap') != -1:
      self.proxy = SOAPpy.WSDL.Proxy(self.options.jiraurl)
    else:
      self.proxy = xmlrpclib.ServerProxy(self.options.jiraurl).jira1

    # We now have enough to connect, so get priorities and types
    try:
      self.get_priorities()
    except Exception,details:
      self.fatal("Failed to get project priorities from Jira: %r" % (details))

    # Run a named Jira API call and return
    if self.options.api is not None:
      try:
        self.call_API(self.options.api,self.args)
      except Exception, details:
        self.fatal("API error: bad method or args: %s" % details)
      return

    # Create a set of Issues based on a YAML project file
    if self.options.template is not None:
      self.create_issues_from_template()
      return

    # Link two existing IDs
    if self.options.link is not None:
      (fromId,type,toId) = self.options.link.split(',')
      print "Create '%s' link from '%s' to '%s'" % (type,fromId,toId)
      result = self.link_issues(fromId,type,toId)
      return

    # UnLink two existing IDs
    if self.options.unlink is not None:
      (fromId,type,toId) = self.options.unlink.split(',')
      print "Remove '%s' link from '%s' to '%s'" % (type,fromId,toId)
      result = self.unlink_issues(fromId,type,toId)
      return

    # Make one issue a sub-task of another
    if self.options.subtask is not None:
      (parent,child) = self.options.subtask .split(',')
      print "Make '%s' a subtask of '%s'" % (child,parent)
      result = self.subtask_link(parent,child)
      return

    # Comment on an existing issue ID
    if self.options.comment is not None:
      if self.options.issueID is None:
        self.fatal("Specify an issue ID to comment on")
      else:
        if self.options.noop:
          print "Add comment to %s: %s" % (self.options.issueID,self.options.comment)
          return
        self.add_comment(self.options.issueID,self.options.comment)
        return

    # Display a specified issue ID
    if self.options.display:

      if self.options.issueID is None:
        self.logger.error("Please specify an issue ID")
        return

      # Get the issue to display
      try:
        issue = self.get_issue(self.options.issueID)
        print "Issue: %s" % self.options.issueID
      except Exception, details:
        print "There was an error fetching %s. Reason: %r" % (self.options.issueID,details)
        return

      if issue.__class__ is SOAPpy.Types.structType:
        inspect(issue)

      else:
        for (k,v) in issue.items():
          print "%15s: %s" % (k,v)

      # Display linked issues... only with SOAP
      if issue.__class__ is SOAPpy.Types.structType:
        links = self.get_issue_links(self.options.issueID)
        ids = []
        for link in links:
          #inspect(link)
          ids.append(getattr(link,'key'))
        print "Linked to this issue:"
        print "%r" % ids

      return

    if self.options.remaining is not None:
      self.update_estimate(self.options.remaining,self.options.issueID)
      return

    # Create an issue object
    issue = self.create_issue_obj()

    # Modify existing issue
    if self.options.issueID is not None:
      # Modify existing issue
      self.modify_issue(self.options.issueID,issue)
      return

    # Create a new issue
    try:
      self.create_issue(issue)
    except Exception, details:
      self.fatal("Failed to create issue.  Reason: %r" % details)

def main():
  A = Jiraclient()
  A.run()

if __name__ == "__main__":
  main()

