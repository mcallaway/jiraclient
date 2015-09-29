#!/usr/bin/python
#
# jiraclient.py
#
# A Python Jira REST Client
#
# (C) 2007,2008,2009,2010,2011,2012: Matthew Callaway
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

import getpass
import os
import pprint
import re
import sys
import logging, inspect, logging.handlers
import stat
from optparse import OptionParser
import ConfigParser
import json
import base64
import datetime
import itertools
from restkit import Resource
from restkit.errors import Unauthorized

pp = pprint.PrettyPrinter(indent=4)
time_rx = re.compile('^\d+[mhdw]$')
session_rx = re.compile("session timed out")

def time_is_valid(value):
  m = time_rx.search(value)
  if not m:
    return False
  return True

class IndentFormatter(logging.Formatter):
    def __init__( self, fmt=None, datefmt=None ):
        logging.Formatter.__init__(self, fmt, datefmt)
        self.baseline = len(inspect.stack())
    def format( self, rec ):
        stack = inspect.stack()
        rec.indent = ' '*(len(stack)-self.baseline)
        rec.function = stack[8][3]
        out = logging.Formatter.format(self, rec)
        del rec.indent; del rec.function
        return out

class Issue(object):

  def __init__(self):
    self.summary      = ''
    self.environment  = ''
    self.description  = ''
    self.duedate      = ''
    self.project      = { 'id': None }
    self.issuetype    = { 'id': None }
    self.assignee     = { 'name': None }
    self.priority     = { 'id': None }
    self.parent       = { 'key': None }
    self.timetracking = { 'originalEstimate': None }
    self.labels       = []
    self.versions     = [ { 'id': None } ]
    self.fixVersions  = [ { 'id': None } ]
    self.components   = [ { 'id': None } ]

  def __repr__(self):
    text = "%s(" % (self.__class__.__name__)
    for attr in dir(self):
      if attr.startswith('_'): continue
      a = getattr(self,attr)
      if callable(a): continue
      text += "%s=%r," % (attr,a)
    text += ")"
    return text

class SearchableDict(dict):
  def find_key(self,val):
      """return the key of dictionary dic given the value"""
      items = [k for k, v in self.iteritems() if v == val]
      if items: return items.pop()
      else: return None
  def find_value(self,key):
      """return the value of dictionary dic given the key"""
      if self.has_key(key): return self[key]
      else: return None

class Jiraclient(object):
  version = "2.1.7"
  def __init__(self):
    self.issues_created = []
    self.proxy   = Resource('', filters=[])
    self.pool    = None
    self.restapi = None
    self.token   = None
    self.cookie  = None
    self.maps    = {
      'project'     : SearchableDict(),
      'priority'    : SearchableDict(),
      'issuetype'   : SearchableDict(),
      'versions'    : SearchableDict(),
      'fixversions' : SearchableDict(),
      'components'  : SearchableDict(),
      'resolutions' : SearchableDict(),
      'transitions' : SearchableDict(),
      'customfields': SearchableDict()
    }

  def fatal(self,msg=None):
    self.logger.fatal(msg)
    sys.exit(1)

  def print_version(self):
    print "jiraclient version %s" % self.version

  def parse_args(self):
    usage = """%prog [options]

 Sample Usage:
  - Standard issue creation in project named INFOSYS:
    jiraclient.py -u 'username' -p 'jirapassword' -A 'auser' -P INFOSYS -T task -S 'Do some task'

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
      default=os.path.join(os.environ["HOME"],'.jiraclientrc'),
    )
    optParser.add_option(
      "--sessionfile",
      action="store",
      dest="sessionfile",
      help="Store authentication token in this file",
      default=os.path.join(os.environ["HOME"],'.jira-session'),
    )
    optParser.add_option(
      "-a","--api",
      action="store",
      dest="api",
      help="Call this API method",
      default=None,
    )
    optParser.add_option(
      "--jsondata",
      action="store",
      dest="jsondata",
      help="JSON data for use with the API option",
      default=None,
    )
    optParser.add_option(
      "--method",
      action="store",
      dest="method",
      help="HTTP method for use with the API option",
      default="get",
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
      "--labels",
      action="store",
      dest="labels",
      help="Comma separated list of labels to apply to new issue",
      default=None,
    )
    optParser.add_option(
      "--link",
      action="store",
      dest="link",
      help="Given link=A,linkType,B links issues A and B with the named link type (eg. Depends)",
      default=None,
    )
    optParser.add_option(
      "--unlink",
      action="store",
      dest="unlink",
      help="Given link=A,linkType,B unlinks issues A and B with the named link type (eg. Depends)",
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
      "--norcfile",
      action="store_true",
      dest="norcfile",
      help="Do not parse issue defaults when using --template",
      default=False,
    )
    optParser.add_option(
      "-n","--noop",
      action="store_true",
      dest="noop",
      help="Do everything locally, never call to the remote API",
      default=False,
    )
    optParser.add_option(
      "--nopost",
      action="store_true",
      dest="nopost",
      help="Do everything except POST and PUT methods, ie. no creation events",
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
      "-s","--spent",
      action="store",
      dest="timespent",
      help="Jira issue 'time spent'",
      default=None,
    )
    optParser.add_option(
      "-R","--resolve",
      action="store",
      dest="resolve",
      help="Resolve issue with the given resolution, eg: 'fixed','incomplete',etc.",
      default=None,
    )
    optParser.add_option(
      "-t","--timetracking",
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
      "-F","--fixVersions",
      action="store",
      dest="fixVersions",
      help="Jira project 'fix versions', comma separated list",
      default=None,
    )
    optParser.add_option(
      "-H","--epic-theme",
      action="store",
      dest="epic_theme",
      help="Set the epic/theme for the issue",
      default=None,
    )
    optParser.add_option(
      "--epic-link",
      action="store",
      dest="epic_link",
      help="Set the Epic Link for the issue",
      default=None,
    )
    optParser.add_option(
      "--epic-name",
      action="store",
      dest="epic_name",
      help="Set the epic name for the issue",
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
      "-T","--issuetype",
      action="store",
      dest="issuetype",
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
      "-V","--affecstVersions",
      action="store",
      dest="affectsVersions",
      help="Jira project 'affects versions', comma separated list",
      default=None,
    )
    optParser.add_option(
      "--parent",
      action="store",
      dest="parent",
      help="Make the given issue a subtask of this issue key",
      default=None,
    )
    optParser.add_option(
      "--prefix",
      action="store",
      dest="prefix",
      help="Specify prefix text to prepend to all Issue summaries",
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
    optParser.add_option(
      "-w","--worklog",
      action="store",
      dest="worklog",
      help="Log work with this given text string, use this in conjunction with --spent and --remaining",
      default=None,
    )
    optParser.add_option(
      "--delete",
      action="store_true",
      dest="delete",
      help="Delete the issue specified by --issue",
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
    fmt = "%(asctime)s %(name)s[%(process)d]: %(levelname)s: %(indent)s %(message)s"
    #fmtr = logging.Formatter(fmt,datefmt)
    fmtr = IndentFormatter(fmt,datefmt)
    handler.setFormatter(fmtr)
    logger.handlers = []
    logger.addHandler(handler)
    logger.setLevel(logging._levelNames[loglevel])
    self.logger = logger

  def read_config(self):
    self.logger.debug("read config %s" % self.options.config)
    parser = ConfigParser.ConfigParser()
    parser.optionxform = str

    if self.options.config is not None:

      if not os.path.exists(self.options.config):
        # Write a basic rc file
        fd = open(self.options.config,'w')
        fd.write('# .jiraclientrc\n')
        fd.write('[jiraclient]\n')
        fd.write('jiraurl = \n')
        fd.write('user = %s\n' % os.environ["USER"])
        fd.write('[issues]\n')
        fd.write('#project = INFOSYS\n')
        fd.write('#issuetype = story\n')
        fd.write('#priority = Normal\n')
        fd.write('#assignee = \n')
        fd.write('#components = \n')
        fd.write('#fixVersions = \n')
        fd.close()
        os.chmod(self.options.config,int("600",8))

      if stat.S_IMODE(os.stat(self.options.config).st_mode) != int("600",8):
        self.logger.warning("Config file %s is not mode 600" % (self.options.config))
      try:
        parser.readfp(file(self.options.config,'r'))
      except ConfigParser.ParsingError:
        self.logger.warning("Body has multiple lines, truncating...")
      except Exception, details:
        self.fatal("Unable to parse file at %r: %s" % (self.options.config,details))

    for (k,v) in (parser.items('jiraclient')):
      if not hasattr(self.options,k):
        # You can't set in rcfile something that isn't also an option.
        self.fatal("Unknown option: %s" % k)
      if getattr(self.options,k) is None:
        self.logger.debug("take value %s for %s from rc file" % (v,k))
        setattr(self.options,k,v)

  def read_issue_defaults(self):
    self.logger.debug("read issue defaults %s" % self.options.config)
    parser = ConfigParser.ConfigParser()
    parser.optionxform = str
    try:
      parser.readfp(file(self.options.config,'r'))
    except ConfigParser.ParsingError:
      self.logger.warning("Body has multiple lines, truncating...")
    except Exception, details:
      self.fatal("Unable to parse file at %r: %s" % (self.options.config,details))

    for (k,v) in (parser.items('issues')):
      if not hasattr(self.options,k):
        # You can't set in rcfile something that isn't also an option.
        self.fatal("Unknown issue attribute: %s" % k)
      if getattr(self.options,k) is None:
        self.logger.debug("take value %s for %s from rc file" % (v,k))
        setattr(self.options,k,v)

  def call_api(self,method,uri,payload=None,full=False):
    self.proxy.uri = "%s/%s" % (self.options.jiraurl, uri)
    call = getattr(self.proxy,method)
    headers = {'Content-Type' : 'application/json'}
    if self.token is not None:
      headers['Authorization'] = 'Basic %s' % self.token
    if self.cookie is not None:
      headers['Cookie'] = '%s' % self.cookie

    self.logger.debug("Call API: %s %s/%s payload=%s headers=%s" % (method,self.options.jiraurl,uri,payload,headers))
    if self.options.noop:
      self.logger.debug("NOOP mode, return before API call")
      return {}
    elif self.options.nopost and ( method.lower() == 'post' or method.lower() == 'put' ):
      self.logger.debug("NOPOST mode, return before API call")
      return {}

    try:
      response = call(headers=headers,payload=payload)
    except Unauthorized:
      if os.path.exists(self.options.sessionfile):
        os.unlink(self.options.sessionfile)
      return None
    except Exception,msg:
      self.fatal("Unhandled API exception for method: %s: %s" % (self.proxy.uri,msg))

    self.logger.debug("Response: %s" % (response.status_int))
    if full:
      return response
    try:
      data = json.loads(response.body_string())
      return data
    except ValueError:
      return {}

  def get_project_id(self,projectKey):
    if self.maps['project']: return
    if self.options.noop:
      self.maps['project']['0'] = 'noop'
      return
    uri = "%s/%s" % ('rest/api/latest/project', projectKey)
    data = self.call_api("get",uri)
    self.maps['project'][str(data["id"])] = projectKey.lower()

  def get_issue_types(self,projectKey):
    if self.maps['issuetype']: return
    if self.options.noop:
      # minimal set of issue types for tests to work
      self.maps['issuetype']['1'] = 'epic'
      self.maps['issuetype']['2'] = 'story'
      self.maps['issuetype']['3'] = 'task'
      self.maps['issuetype']['4'] = 'sub-task'
    else:
      self.check_auth()
      uri = 'rest/api/latest/issue/createmeta?projectKeys=%s' % (projectKey)
      data = self.call_api("get",uri)
      for item in data['projects'][0]['issuetypes']:
          self.maps['issuetype'][str(item['id'])] = str(item['name'].lower())
    self.logger.debug("types: %s" % self.maps['issuetype'])

  def get_customfields(self,projectKey,issueType):
    if not self.maps['project']: return
    if not self.maps['issuetype']: return
    if issueType in self.maps['customfields']: return
    if self.options.noop:
      # Minimum fields for epics to work for tests to pass.
      tid = self.maps['issuetype'].find_key('epic')
      self.maps['customfields'][str(tid)] = SearchableDict()
      self.maps['customfields'][str(tid)]['customfield_00000'] = 'epic/theme'
      self.maps['customfields'][str(tid)]['customfield_00001'] = 'epic name'
      self.maps['customfields'][str(tid)]['customfield_00002'] = 'epic link'
      for tid in (2,3,4):
        self.maps['customfields'][str(tid)] = SearchableDict()
        self.maps['customfields'][str(tid)]['customfield_00000'] = 'epic/theme'
        self.maps['customfields'][str(tid)]['customfield_00001'] = 'epic link'
    else:
      pid = self.maps['project'].find_key(projectKey.lower())
      #tid = self.maps['issuetype'].find_key(issueType)
      uri = 'rest/api/latest/issue/createmeta?projectIds=%s&issuetypeIds=%s&expand=projects.issuetypes.fields' % (pid,issueType)
      data = self.call_api("get",uri)
      for item in data['projects'][0]['issuetypes']:
        for field in item['fields']:
          if field.startswith('customfield'):
            self.logger.debug("customfield: %s %s" % (field,str(item['fields'][field]['name'].lower())))
            #self.maps['customfields'][str(field)] = str(item['fields'][field]['name'].lower())
            if issueType not in self.maps['customfields'].keys():
              self.maps['customfields'][str(issueType)] = SearchableDict()
            self.maps['customfields'][str(issueType)][str(field)] = str(item['fields'][field]['name'].lower())

  def get_resolutions(self):
    if self.maps['resolutions']: return
    if self.options.noop:
      self.maps['resolutions']['0'] = 'complete'
    else:
      uri = 'rest/api/latest/resolution'
      data = self.call_api("get",uri)
      for item in data:
        self.maps['resolutions'][str(item['id'])] = str(item['name'].lower()) 

  def get_transitions(self,issueKey):
    if self.maps['transitions']: return
    if self.options.noop:
        self.maps['transitions']['0'] = 'noop'
    else:
      uri = 'rest/api/latest/issue/%s/transitions' % issueKey
      data = self.call_api("get",uri)
      for item in data['transitions']:
        item = item['to']
        self.maps['transitions'][str(item['id'])] = str(item['name'].lower()) 

  def get_project_versions(self,projectKey):
    if self.maps['fixversions']: return
    if self.options.noop:
      self.maps['versions']['0'] = 'noop'
    else:
      uri = "%s/%s/%s" % ('rest/api/latest/project', projectKey, 'versions')
      data = self.call_api("get",uri)
      for item in data:
        self.maps['versions'][str(item['id'])] = str(item['name'].lower())
    self.maps['fixversions'] = self.maps['versions']

  def get_project_components(self,projectKey):
    if self.maps['components']: return
    if self.options.noop:
        self.maps['components']['0'] = 'noop'
    else:
      uri = "%s/%s/%s" % ('rest/api/latest/project', projectKey, 'components')
      data = self.call_api("get",uri)
      for item in data:
        self.maps['components'][str(item['id'])] = str(item['name'].lower())

  def get_priorities(self):
    if self.maps['priority']: return
    if self.options.noop:
      self.maps['priority']['0'] = 'noop'
    else:
      uri = 'rest/api/latest/priority'
      data = self.call_api("get",uri)
      for item in data:
        self.maps['priority'][str(item['id'])] = str(item['name'].lower())

  def update_maps_from_jiraserver(self):
    self.logger.debug("update maps from jira server")
    # Need project first.
    # These need to happen before any issue creation or modification
    self.get_project_id(self.options.project)
    self.get_issue_types(self.options.project)
    for itype in self.maps['issuetype']:
      self.get_customfields(self.options.project,itype)
    self.get_project_versions(self.options.project)
    self.get_project_components(self.options.project)
    self.get_resolutions()
    self.get_priorities()
    self.logger.debug("maps: %s" % self.maps)

  def get_serverinfo(self):
    uri = 'rest/api/latest/serverInfo'
    result = self.call_api("get",uri)
    if not result:
      result = {"baseUrl":self.options.jiraurl}
    return result

  def get_issue(self,issueID):
    uri = 'rest/api/latest/issue/%s' % issueID
    return self.call_api("get",uri)

  def delete_issue(self,issueID):
    uri = 'rest/api/latest/issue/%s?deleteSubtasks=true' % issueID
    result = self.call_api('delete',uri)
    self.logger.info("Deleted %s/browse/%s" % (self.get_serverinfo()['baseUrl'], issueID))
    return result

  def resolve_issue(self,issueID,resolution):
    resolution = resolution[0].upper() + resolution[1:].lower()
    self.get_transitions(issueID)
    uri = 'rest/api/latest/issue/%s/transitions' % issueID
    transition_id = self.maps['transitions'].find_key("resolved")
    payload = json.dumps({"transition":{"id": transition_id},"fields":{"resolution":{"name":resolution}}})
    result = self.call_api("post",uri,payload=payload)
    self.logger.info("Resolved %s/browse/%s" % (self.get_serverinfo()['baseUrl'], issueID))
    return result

  def display_issue(self,issueID):
    uri = 'rest/api/latest/issue/%s' % issueID
    result = self.call_api('get',uri)
    print json.dumps(result)

  def fetch_issue(self,issueID):
    uri = 'rest/api/latest/issue/%s' % issueID
    return self.call_api('get',uri)

  def add_comment(self,issueID,comment):
    uri = 'rest/api/latest/issue/%s/comment' % issueID
    comment = json.dumps({'body':comment})
    result = self.call_api('post',uri,payload=comment)
    return result

  def clean_issue(self,issue):
    # We have an Issue with a number of required default values
    # that are often empty.  Remove the empty ones so as to not
    # confuse the API service.
    self.logger.debug("clean issue start: %s" % issue)
    if type(issue) is not dict:
      issue = issue.__dict__
    for k,v in issue.items():
      if not v: issue.pop(k)
      if v == {"id":None}: issue.pop(k)
      if v == {"name":None}: issue.pop(k)
      if v == {"key":None}: issue.pop(k)
      if v == {"originalEstimate":None}: issue.pop(k)
      if v == [{"id":None}]: issue.pop(k)
    self.logger.debug("cleaned issue: %s" % issue)
    return issue

  def create_issue(self,issueObj):
    issue = self.clean_issue(issueObj)
    payload = json.dumps({"fields":issue})
    uri = 'rest/api/latest/issue'
    newissue = self.call_api('post',uri,payload=payload)
    issueID = "NOOP"
    if newissue:
      issueID = newissue["key"]
    self.logger.info("Created %s/browse/%s" % (self.get_serverinfo()['baseUrl'], issueID))
    self.issues_created.append(issue)
    return issueID

  def modify_issue(self,issueID,issueObj):
    issue = self.clean_issue(issueObj)
    self.logger.debug("modify issue: %s %s" % (issueID,issue))
    # FIXME: I'm not sure of a good way to see if we just said --issue with no other options.
    # So this is a hack to check to see if that's the case.
    issuecopy = issue
    if issuecopy.has_key("project"): issuecopy.pop("project")
    if not issuecopy:
      # We specified nothing but --issue, in that case, just display that issue
      # This is like --display --issue FOO-123
      return self.display_issue(issueID)
    payload = json.dumps({"fields":issue})
    uri = 'rest/api/latest/issue/%s' % issueID
    self.call_api('put',uri,payload=payload)
    self.logger.info("Modified issue %s/browse/%s" % (self.get_serverinfo()['baseUrl'], issueID))

  def get_issue_links(self,issueID):
    uri = 'rest/api/latest/issue/%s' % issueID
    data = self.call_api('get',uri)
    return data['fields']['issuelinks']

  def delete_issue_link(self,linkID):
    uri = 'rest/api/latest/issueLink/%s' % linkID
    return self.call_api('delete',uri)

  def get_session(self):
    uri = 'rest/auth/latest/session'
    return self.call_api("get",uri,full=True)

  def read_password(self):
    if not self.options.password:
      print "Please authenticate."
      pw = getpass.getpass("Jira password: ")
      self.options.password = pw

  def check_auth(self):
    if self.options.noop: return
    self.logger.debug("Check authentication")
    sessionfile = self.options.sessionfile

    # Don't allow insecure cookie file
    if os.path.exists(sessionfile) and stat.S_IMODE(os.stat(sessionfile).st_mode) != int("600",8):
        self.logger.error("session file %s is not mode 600, forcing new session" % (sessionfile))
        os.unlink(sessionfile)

    # Read existing session
    if os.path.exists(sessionfile):
      self.logger.debug("read auth session")
      fd = open(sessionfile,'r')
      self.cookie = fd.read()
      fd.close()
      # Check if it's still valid
      response = self.get_session()
      if type(response).__name__ == 'Response' and response.status_int == 200:
        # Cookie still valid, use it
        return
      # Get a new cookie below
      self.cookie = None
      if os.path.exists(sessionfile):
        os.unlink(sessionfile)

    self.logger.debug("make auth session")
    if not self.options.password:
      self.read_password()

    self.token = base64.b64encode("%s:%s" % (self.options.user, self.options.password))
    response = self.get_session()
    if response is None:
      self.fatal("Login failed")

    if type(response).__name__ == 'Response' and response.status_int == 200:
      m = re.match(r'JSESSIONID=(.*?);',response.headers['Set-Cookie'])
      if m:
        cookie = m.group(0)
        self.cookie = cookie
      else:
        return

    # Clear token and use cookie
    self.token = None
    fd = open(sessionfile,'w')
    fd.write(cookie)
    fd.close()
    os.chmod(sessionfile,int("600",8))

  def update_dict_value(self,adict,attribute,value):
    # Take a dict like { 'id': something } and put in the right value
    # If the value is a string of digits, use it directly.
    # If the value is a string, look up its id in a map.
    # If the value is a dict, use it directly.
    newdict = {}
    key = adict.keys()[0]
    if key == 'id':
      id_of_value = None
      if self.options.noop:
        # Empty maps in noop mode return fake IDs
        id_of_value = '00'
      else:
        amap = self.maps[attribute.lower()]
        if type(value) is str and value.isdigit():
          # Special case if we specify an ID directly
          if amap.has_key(str(value)):
            id_of_value = value
          else:
            self.fatal("You specified unknown ID '%s' for attribute '%s', known values are: %s" % (value,attribute,amap))
        else:
          # Find the id of the value from the maps
          id_of_value = amap.find_key(value.lower())
      if id_of_value is None:
        self.fatal("You specified '%s' for attribute '%s', known values are: %s" % (value,attribute,amap))

      newdict['id'] = str(id_of_value)
    else:
      # Key is 'name' or 'key' and needs no lookup
      #self.logger.debug("value type: %s" % (type(value)))
      if type(value) is str or type(value) is unicode:
        newdict[key] = str(value)
      elif type(value) is dict:
        newdict[key] = value
      else:
        raise ValueError("Unhandled value for input: %s %s" % (key,value))
    self.logger.debug("convert %s to %s" % (adict,newdict))
    return newdict

  def update_issue_obj(self,issue,attribute,value):
    self.logger.debug("update issue (%s) attribute (%s) value (%s)" % (issue,attribute,value))

    if not attribute or not value:
      # Return unmodified issue
      return issue

    if type(value) is dict or type(value) is list:
      # If value is a dict, it's already been looked up in some previous
      # call of this method, like in create_issues_from_template()
      setattr(issue,attribute,value)
      return issue

    if attribute.startswith("customfield"):
      # Custom fields aren't class attributes, just add them
      setattr(issue,attribute,value)
      return issue

    itype = issue.issuetype['id']
    if itype in self.maps['customfields'].keys() and attribute in self.maps['customfields'][itype].values():
      if attribute == 'epic/theme':
        setattr(issue,self.maps['customfields'][itype].find_key(str(attribute)),[value])
      if attribute == 'epic link':
        setattr(issue,self.maps['customfields'][itype].find_key(str(attribute)),value)
      if attribute == 'epic name':
        setattr(issue,self.maps['customfields'][itype].find_key(str(attribute)),value)
      return issue

    # Fail if we specified an unknown attribute that isn't a customfield
    customfields = list(set(itertools.chain( *[ x.values() for x in self.maps['customfields'].values() ] )))
    if not hasattr(Issue(),attribute) and attribute not in customfields:
      self.fatal("Unknown issue attribute: %s" % attribute)

    attr = getattr(Issue(),attribute)
    # Is the attr a string, list of strings, dict or list of dicts?
    if type(attr) is str:
      # If attr is a string, set the value and we're done
      self.logger.debug("set str attr: %s %s" % (attribute,value))
      setattr(issue,attribute,str(value))
    elif type(attr) is list:
      # List of dicts or list of labels
      self.logger.debug("updating list %s" % attr)
      if len(attr) == 0 or type(attr[0]) is str:
        # This is the labels list, append and we're done
        attr = getattr(issue,attribute)
        attr.append(str(value))
      else:
        # This is a list of dicts.
        # Assume we can have only one value...
        item = attr.pop()
        # Now modify the value...
        newvalue = self.update_dict_value(item,attribute,value)
        self.logger.debug("set issue (%s) attribute (%s) value (%s)" % (issue,attribute,newvalue))
        setattr(issue,attribute,[newvalue])
    elif type(attr) is dict:
      setattr(issue,attribute,self.update_dict_value(attr,attribute,value))

    return issue

  def update_issue_obj2(self,issue,key,value):
    # This method handles Issue's complex attribute types.
    #
    # Input values come from CLI or rc file, so are all strings
    # potentially with comma separated lists.  To keep things
    # simple, let's just assume all CLI and rc file input are not lists.
    #
    # Use case examples:
    #   summary is a string
    #   project is a dict with id
    #   versions is a list of dicts with id
    #
    # So we say update issue attribute named "key" with value "value"
    #   where the attribute might be a string, list of strings, dict
    #   or list of dicts.  Where if the thing is a dict, it might
    #   be keyed on "id", "key", "name" etc.
    #   If the key is "id" we convert "value" to id of value from self.maps
    self.logger.debug("update issue object: %s %s" % (key,value))

    if not key or not value: return

    if not hasattr(issue,key):
      self.logger.debug("set simple attr: %s %s" % (key,value))
      setattr(issue,key,value)

    attr = getattr(issue,key)
    # attribute_map is one of self.maps to find the jira DB id value
    # corresponding to a string name.
    attribute_map = None
    # attribute_id is the numerical id of the desired value.
    attribute_id = None
    # So if we're saying: set issue's "component" to "CSA" then
    # components are in self.maps['component'] and value "CSA" has id 10020

    # Does the 'key' exist in self.maps to provide an ID?
    # In noop mode maps will be empty.
    if self.options.noop:
      # If in noop mode, we haven't set up self.maps, so just use fake values
      if self.maps.has_key(key.lower()):
        attribute_map = self.maps[key.lower()]
      attribute_id = value
    elif type(value) is int:
      # If we say set issue attr to 10, an int, then we don't have to look it up.
      attribute_id = value
    elif self.maps.has_key(key.lower()):
      self.logger.debug("update with key value : %s %s" % (key,value))
      if type(value) is str:
        self.logger.debug("look at: %s" % self.maps[key.lower()])
        attribute_map = self.maps[key.lower()]
        attribute_id = attribute_map.find_key(value.lower())
        self.logger.debug("use id %s for %s" % (attribute_id,value))
      else:
        self.logger.debug("use value for: %s %s" % (key,value))
        setattr(issue,key,value)
        return issue
      if not attribute_id:
        if not self.options.noop:
          self.fatal("No value known for %s = %s" % (key,value.lower()))
        return issue

    # Plain string assignment
    if type(attr) is str:
      self.logger.debug("use str for: %s %s" % (key,value))
      setattr(issue,key,str(value))

    # Lists might be lists of strings or lists of dicts
    # 'labels' is the only list of just strings
    if type(attr) is list:
      if key == 'labels':
        attr.append(str(value))
      else:
        try:
          # remove initial empty value if it's there
          attr.pop(attr.index({'id':None}))
        except Exception: pass
        self.logger.debug("set dict for %s %s" % (key,[{'id':str(attribute_id)}]))
        setattr(issue,key,[{'id':str(attribute_id)}])

    if type(attr) is dict:
      self.logger.debug("set dict attr %s %s" % (key,value))
      item = getattr(issue,key)
      if type(value) is dict:
        setattr(issue,key,value)
      elif item.has_key('id'):
        if attribute_map:
          # If this attribute is one with a self.maps entry...
          item['id'] = str(attribute_id)
        else:
          item['id'] = str(value)
      elif item.has_key('name'):
        item['name'] = str(value)
      elif item.has_key('key'):
        item['key'] = str(value)

    return issue

  def update_issue_from_options(self,issue):
    self.logger.debug("update issue from options: %s" % issue)
    for key in issue.__dict__.keys():
      self.logger.debug("check attr %s" % key)
      if hasattr(self.options,key):
        attr = getattr(self.options,key)
        if attr:
          if key == 'summary' or key == 'description':
            values = [getattr(self.options,key)]
          else:
            values = getattr(self.options,key).split(',')
          for value in values:
            issue = self.update_issue_obj(issue,key,value)
        else:
          self.logger.debug("options has empty value for: %s" % (key))
      else:
        self.logger.debug("options has no value for: %s" % (key))
    self.logger.debug("updated issue: %s" % issue)
    return issue

  def create_issue_obj(self,issuetype,defaults=False,empty=False):
    self.logger.debug("create issue object (%s)" % (defaults))

    # Trigger to parse rc file for issue default values
    if defaults:
      self.read_issue_defaults()

    if self.options.project is None:
      self.fatal("You must specify a project key")

    # Creates an Issue object based on CLI args and config file.
    # We do this for create and modify operations.
    issue = Issue()
    if empty:
      return issue

    # FIXME: is order right here?  Do these go after update_issue_from_options below?

    # Now update issue attributes from CLI options that are not themselves
    # issue attributes.

    if self.options.timetracking:
      setattr(issue,'timetracking',{"originalEstimate": self.options.timetracking})
    if self.options.remaining:
      setattr(issue,'timetracking',{"remainingEstimate": self.options.remaining})

    # The not noop version updates data (eg. IDs) from jiraserver.
    # We need self.maps for issue types and other attributes.
    self.update_maps_from_jiraserver()

    # Set attributes from options default values and rc file.
    issue = self.update_issue_from_options(issue)

    # Set issue type if we said to.
    if issuetype is not None:
        issuetype = issuetype.lower()
        itype = self.maps['issuetype'].find_key(issuetype)
        if itype is None:
          self.fatal("Failed to set issue type to '%s', no issue id found in %s" % (issuetype,self.maps['issuetype']))
        self.logger.debug("set issue type to %s" % (itype))
        issue.issuetype['id'] = itype

    if not issue.project:
      self.fatal("Issue must have a project")
    if not issue.issuetype:
      self.fatal("Issue must have an issuetype")
    if issue.parent["key"] is not None and issue.issuetype['id'] != str(self.maps['issuetype'].find_key("sub-task")):
      self.fatal("Issue type must be sub-task for --parent to be valid")

    # Set Epic attributes via customfield
    if self.options.epic_theme and issue.issuetype['id'] is not None and \
     self.maps['customfields'][issue.issuetype['id']].find_value('epic/theme') is not None:
      attr = self.maps['customfields'][issue.issuetype['id']].find_value('epic/theme')
      setattr(issue,attr,[self.options.epic_theme])
    if self.options.epic_name and issue.issuetype['id'] is not None and \
     self.maps['customfields'][issue.issuetype['id']].find_key('epic name'):
      attr = self.maps['customfields'][issue.issuetype['id']].find_key('epic name')
      setattr(issue,self.maps['customfields'][issue.issuetype['id']].find_key('epic name'),self.options.epic_name)

    return issue

  def log_work(self,issueID):
    '''/rest/api/2/issue/{issueIdOrKey}/worklog?adjustEstimate&newEstimate&reduceBy'''
    comment = self.options.worklog
    spent = self.options.timespent
    if spent is not None:
      m = time_rx.match(spent)
      if not m:
        self.logger.warning("Time spent has dubious format: %s: no action taken" % (spent))
        return
    remaining = self.options.remaining
    if remaining is not None:
      m = time_rx.match(remaining)
      if not m:
        self.logger.warning("Time remaining has dubious format: %s: no action taken" % (remaining))
        return

    baseuri = 'rest/api/latest/issue/%s/worklog' % issueID
    dt_today = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.000-0000");

    args = None
    if spent is None and remaining is None:
      # time spent must not be null, so default to 1m
      worklog = {'started':dt_today,'comment':comment,'timeSpent':'1m'}
      payload = json.dumps(worklog)
      args = ('post',baseuri)
    elif spent is None:
      # remaining has been set, but not spent
      uri = "%s?adjustEstimate=new&newEstimate=%s" % (baseuri,remaining)
      worklog = {'comment':comment}
      payload = json.dumps(worklog)
      args = ('post',uri)
    elif remaining is None:
      # spent set, auto adjust
      uri = "%s?adjustEstimate=auto" % (baseuri)
      worklog = {'timeSpent':spent,'comment':comment}
      payload = json.dumps(worklog)
      args = ('post',uri)
    else:
      # spent set and remaining set
      uri = "%s?adjustEstimate=new&newEstimate=%s" % (baseuri,remaining)
      worklog = {'timeSpent':spent,'comment':comment}
      payload = json.dumps(worklog)
      args = ('post',uri)

    self.logger.debug("Log work: %s %s" % (args,payload))
    return self.call_api(*args,payload=payload)

  def link_issues(self,issueFrom,linkType,issueTo):
    self.logger.debug("Link %s -> %s -> %s" % (issueFrom,linkType,issueTo))
    uri = 'rest/api/latest/issueLink'
    payload = json.dumps({"type":{"name":linkType},"inwardIssue":{"key":issueFrom},"outwardIssue":{"key":issueTo},"comment":{"body":self.options.comment}})
    return self.call_api('post',uri,payload=payload)

  def unlink_issues(self,issueFrom,linkType,issueTo):
    self.logger.debug("Unlink %s -> %s -> %s" % (issueFrom,linkType,issueTo))
    for link in self.get_issue_links(issueFrom):
      if link["outwardIssue"]["key"] == issueTo and link["type"]["name"].lower() == linkType.lower():
        return self.delete_issue_link(link["id"])
    if linkType == "jira_subtask_link":
      # issueFrom has 'subtask' field, issueTo has 'parent' field.
      # Not sure yet if I can just delete those in a modify_issue action.
      self.logger.info("Unlinking subtasks is currently unsupported")

  def subtask_link(self,parent,child):
    # Modify child issue:
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
    # Must set the subtask link first, then change the issue type of child
    self.logger.debug("Set subtask link: %s -> %s" % (parent,child))
    self.link_issues(parent,'jira_subtask_link',child)
    # Change issue type to subtask and set parent attribute on child issue
    issue = self.create_issue_obj(empty=True,issuetype='sub-task')
    issue = self.update_issue_obj(issue,'parent',parent)
    self.modify_issue(child,issue)

  def epic_link(self,idlist,epic):
    # Make the named task part of the named epic.
    # This makes use of Greenhopper's REST interface as of GH 6.x
    payload = json.dumps({"ignoreEpics":"true","issueKeys":idlist})
    uri = "rest/greenhopper/1.0/epics/%s/add" % epic
    self.call_api('put',uri,payload=payload)
    self.logger.info("Added issues to epic %s: %s/browse/%s" % (epic, self.get_serverinfo()['baseUrl'], idlist))

  def create_issues_from_template(self):
    import yaml
    self.logger.debug("Create issues from template")

    if not self.options.template == "-" and not os.path.exists(self.options.template):
      self.fatal("No such file: %s" % self.options.template)

    # This isn't "real" recursion because as we get deeper the thing we represent
    # goes from Epic to Story to Subtask, which are different datatypes in Jira.
    try:
      if self.options.template == "-":
        yamldata = yaml.load(sys.stdin)
      else:
        yamldata = yaml.load(file(self.options.template,"r"))
    except Exception,details:
      self.fatal("Failed to parse YAML template: %s" % details)

    stories = None
    subtasks = None
    if yamldata.has_key('stories'):
      stories = yamldata.pop('stories')
    if yamldata.has_key('subtasks'):
      subtasks = yamldata.pop('subtasks')

    # Should we use the rc file for issue defaults?
    defaults = not self.options.norcfile

    # First create the "Epic", which might be an actual Epic or some custom
    # issue type that is a duplicate of an Epic.  Create this Epic first so we
    # can use its Key as epic_theme/epic_link in other issues.
    issuetype = 'epic'
    # The sub type is the Issue type for project milestones.
    subtype = 'story'
    if 'type' in yamldata.keys():
      issuetype = yamldata.pop('type').lower()
    if 'subtype' in yamldata.keys():
      subtype = yamldata.pop('subtype').lower()

    epic = self.create_issue_obj(defaults=defaults,issuetype=issuetype)
    for (k,v) in yamldata.items():
      epic = self.update_issue_obj(epic,k,v)
    eid = self.create_issue(epic)

    # Modify the epic we just created to set its own theme
    self.modify_issue(eid,{self.maps['customfields'][epic.issuetype['id']].find_key('epic/theme'):[eid]})
    # Update the epic issue object so that epic/theme is inherited for tasks we're about to create
    epic = self.update_issue_obj(epic,self.maps['customfields'][epic.issuetype['id']].find_key('epic/theme'),[eid])

    # create subtasks for eid, inheriting from epic
    if subtasks:
      idlist = []
      for subtask in subtasks:
        self.logger.debug("create subtask inheriting from epic")
        issue = self.create_issue_obj(defaults=defaults,issuetype='sub-task')
        for (k,v) in epic.__dict__.items():
          if k in ('description','summary','issuetype') or (k.startswith('customfield') and \
                  k != self.maps['customfields'][epic.issuetype['id']].find_key('epic/theme') and \
                  k != self.maps['customfields'][epic.issuetype['id']].find_key('epic link')): continue
          issue = self.update_issue_obj(issue,k,v)
        for (k,v) in subtask.items():
          issue = self.update_issue_obj(issue,k,v)
        issue = self.update_issue_obj(issue,'parent',eid)
        stid = self.create_issue(issue)
        idlist.append(stid)

      self.epic_link(idlist,eid)

    # create stories for eid, inheriting from epic
    if stories:
      idlist = []
      for story in stories:
        subtasks = None
        if story.has_key('subtasks'):
          subtasks = story.pop('subtasks')

        self.logger.debug("create story inheriting from epic")
        issue = self.create_issue_obj(defaults=defaults,issuetype=subtype)
        for (k,v) in epic.__dict__.items():
          if k in ('description','summary','issuetype') or (k.startswith('customfield') and \
                  k != self.maps['customfields'][epic.issuetype['id']].find_key('epic/theme') and \
                  k != self.maps['customfields'][epic.issuetype['id']].find_key('epic link')): continue
          issue = self.update_issue_obj(issue,k,v)
        for (k,v) in story.items():
          issue = self.update_issue_obj(issue,k,v)
        sid = self.create_issue(issue)
        idlist.append(sid)

        if subtasks:
          # create subtasks for stories of epic, inheriting from epic
          for subtask in subtasks:
            self.logger.debug("create story subtask inheriting from epic")
            issue = self.create_issue_obj(defaults=defaults,issuetype='sub-task')
            for (k,v) in epic.__dict__.items():
              if k in ('description','summary','issuetype') or (k.startswith('customfield') and \
                  k != self.maps['customfields'][epic.issuetype['id']].find_key('epic/theme') and \
                  k != self.maps['customfields'][epic.issuetype['id']].find_key('epic link')): continue
              issue = self.update_issue_obj(issue,k,v)
            for (k,v) in subtask.items():
              issue = self.update_issue_obj(issue,k,v)
            issue = self.update_issue_obj(issue,'parent',sid)
            stid = self.create_issue(issue)
            idlist.append(stid)

      self.epic_link(idlist,eid)

    self.logger.info("Created issue %s/browse/%s" % (self.get_serverinfo()['baseUrl'], eid))

  def act_on_existing_issue(self):

    (project,issue) = self.options.issueID.split('-')
    self.options.project = project

    # Delete a given issue
    if self.options.delete is True:
      return self.delete_issue(self.options.issueID)

    # Display a given issue
    if self.options.display:
      return self.display_issue(self.options.issueID)

    # Make one issue a sub-task of another
    if self.options.parent is not None:
      return self.subtask_link(self.options.parent,self.options.issueID)

    # Comment on an existing issue ID
    if self.options.comment is not None:
      return self.add_comment(self.options.issueID,self.options.comment)

    # Modify worklog and time
    if self.options.worklog or self.options.timespent or self.options.remaining:
      return self.log_work(self.options.issueID)

    # Resolve a given existing issue ID
    if self.options.resolve is not None:
      return self.resolve_issue(self.options.issueID,self.options.resolve)

    # Set epic link if specified
    if self.options.epic_link:
      self.epic_link([self.options.issueID],self.options.epic_link)

    # Modify existing issue
    if self.options.issueID is not None:
      i = self.fetch_issue(self.options.issueID)
      # We need to know issue type to have access to custom fields
      try:
        itype = i['fields']['issuetype']['name']
      except Exception, details:
        self.fatal("Cannot determine issue type of issue %s: %s" % (self.options.issueID, details))
      issue = self.create_issue_obj(itype,defaults=False)
      return self.modify_issue(self.options.issueID,issue)

  def setup(self):

    self.parse_args()
    self.prepare_logger()
    self.read_config()
    self.check_auth()

  def run(self):

    self.setup()

    if self.options.version:
      self.print_version()
      return

    # Notify the user if noop is on
    if self.options.noop:
      self.logger.info("NOOPMODE: API will not be called")

    if not self.options.user:
      self.fatal("Please specify Jira user")

    if not self.options.jiraurl:
      self.fatal("Please specify the Jira URL")

    # Run a named Jira API call and return
    if self.options.api is not None:
      # Set payload
      payload = None
      if self.options.jsondata is not None:
        self.logger.debug("read json data %s" % self.options.jsondata)
        if self.options.jsondata.startswith("{"):
          payload = json.dumps(json.loads(self.options.jsondata))
        else:
          jsonpath = os.path.expanduser(self.options.jsondata)
          if os.path.exists(jsonpath):
            fd = open(jsonpath,'r')
            try:
              jsondata = fd.read()
            except Exception,msg:
              self.fatal("Error reading jsondata: %s" % msg)
            fd.close()
            try:
              payload = json.dumps(json.loads(jsondata))
            except Exception,msg:
              self.fatal("Error parsing jsondata: %s" % msg)
          else:
            self.fatal("API error: file not found: %s" % self.options.jsondata)
      # Send payload with method
      try:
        response = self.call_api(self.options.method.lower(),self.options.api,payload=payload)
        print json.dumps(response)
      except Exception, details:
        self.fatal("API error: bad method: %s" % details)
      return

    # Link two existing IDs
    if self.options.link is not None:
      (fromId,linktype,toId) = self.options.link.split(',')
      return self.link_issues(fromId,linktype,toId)

    # UnLink two existing IDs
    if self.options.unlink is not None:
      (fromId,linktype,toId) = self.options.unlink.split(',')
      return self.unlink_issues(fromId,linktype,toId)

    # Create a set of Issues based on a YAML project file
    if self.options.template is not None:
      return self.create_issues_from_template()

    # Act on an existing Jira Issue
    if self.options.issueID is not None:
      return self.act_on_existing_issue()

    # Create a new issue
    if self.options.summary is not None:
      defaults = not self.options.norcfile
      issue = self.create_issue_obj(self.options.issuetype,defaults=defaults)
      try:
        return self.create_issue(issue)
      except Exception, details:
        self.fatal("Failed to create issue. Reason: %r" % details)

    # Set epic link if specified
    if self.options.epic_link:
      return self.epic_link([issueID],self.options.epic_link)

    # Add a work log, possibly updating remaining estimate
    if self.options.worklog is not None:
      return self.log_work(issueID)

    # Resolve the just created issue
    if self.options.resolve is not None:
      return self.resolve_issue(issueID,self.options.resolve)

    # If you got here, you didn't ask to do anything
    self.logger.info("Nothing to do. Seek --help.")

def main():
  A = Jiraclient()
  try:
    A.run()
  except KeyboardInterrupt:
    print "Exiting..."
    return

if __name__ == "__main__":
  main()

# vim: ts=2
