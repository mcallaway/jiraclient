
import pprint
import sys
import os
import unittest
#import json
import base64
from DictDiffer import DictDiffer

if os.path.exists("./jiraclient/"):
  sys.path.insert(0,"./jiraclient/")

import jiraclient
#from restkit import BasicAuth

pp = pprint.PrettyPrinter(depth=4,stream=sys.stdout)

class TestUnit(unittest.TestCase):

  def setUp(self):
    self.c = jiraclient.Jiraclient()
    self.c.parse_args()
    self.c.options.config = "./test/data/jiraclientrc-001"
    self.c.options.sessionfile = "./test/data/jira-session"
    self.c.options.loglevel = "DEBUG"
    self.c.options.nopost = True
    self.c.options.noop = False
    self.c.prepare_logger()
    self.c.read_config()
    # These tests require jirauser have permission to create issues
    self.c.options.user = 'jirauser'
    self.c.options.password = 'jirauser'

  def testLogger(self):
    self.c.logger.info('info')
    self.c.logger.warn('warn')
    self.c.logger.error('error')
    self.c.logger.fatal('fatal')

  def testTimeIsValid(self):
    assert jiraclient.time_is_valid('1s') is False
    assert jiraclient.time_is_valid('1m') is True
    assert jiraclient.time_is_valid('1h') is True
    assert jiraclient.time_is_valid('1d') is True
    assert jiraclient.time_is_valid('1w') is True
    assert jiraclient.time_is_valid('1q') is False
    assert jiraclient.time_is_valid('0.1m') is False

  def testFatal(self):
    self.assertRaises(SystemExit,self.c.fatal)

  def testReadConfig(self):
    assert self.c.options.user == 'jirauser'
    assert self.c.options.jiraurl == 'https://jira.gsc.wustl.edu'

  def testGetProjectId(self):
    self.c.get_project_id('INFOSYS')
    assert self.c.maps['project']['10001'] == 'infosys'

  def testGetSession(self):
    self.c.token = base64.b64encode("%s:%s" % (self.c.options.user, self.c.options.password))
    self.c.cookie = None
    response = self.c.get_session()
    assert response.status_int == 200

  def testCheckAuth(self):
    if os.path.exists(self.c.options.sessionfile):
      os.unlink(self.c.options.sessionfile)

    # Test success
    self.c.check_auth()
    assert self.c.cookie.startswith("JSESSIONID")

    self.c.cookie = None
    if os.path.exists(self.c.options.sessionfile):
      os.unlink(self.c.options.sessionfile)

    # Test failure
    self.c.options.password = "wrong"
    self.assertRaises(SystemExit,self.c.check_auth)
    assert self.c.cookie is None

    self.setUp()

  def testGetIssueTypes(self):
    self.c.get_issue_types('INFOSYS')
    pp.pprint(self.c.maps['issuetype'])
    desired = { '6': 'epic', '7': 'story', '5': 'sub-task', '3': 'task'}
    diff = DictDiffer(self.c.maps['issuetype'],desired)
    assert diff.areEqual()

  def testGetCustomFields(self):
    self.c.check_auth()
    pp.pprint(self.c.__dict__)
    self.c.get_project_id('INFOSYS')
    assert self.c.maps['project']['10001'] == 'infosys'
    self.c.get_issue_types('INFOSYS')
    assert self.c.maps['issuetype']['6'] == 'epic'
    self.c.get_customfields('INFOSYS','6')
    desired = { '6': {
            'customfield_10010': 'epic/theme',
            'customfield_10002': 'story points',
            'customfield_10003': 'business value',
            'customfield_10000': 'flagged',
            'customfield_10441': 'epic name',
            'customfield_10440': 'epic link'
            }}
    diff = DictDiffer(self.c.maps['customfields'],desired)
    assert diff.areEqual()

  def testGetResolutions(self):
    self.c.get_resolutions()
    desired = {'5': 'cannot reproduce', '6': 'complete', '3': 'duplicate', '1': 'fixed', '4': 'incomplete', '2': "won't fix"}
    diff = DictDiffer(self.c.maps['resolutions'],desired)
    assert diff.areEqual()

  def testGetProjectVersions(self):
    self.c.get_project_versions('INFOSYS')
    assert self.c.maps['versions']['10180'] == 'sprint 2012-1: 1/2 - 1/13'

  def testGetProjectComponents(self):
    self.c.get_project_components('INFOSYS')
    assert self.c.maps['components']['10111'] == 'csa'

  def testGetPriorities(self):
    self.c.get_priorities()
    assert self.c.maps['priority']['3'] == 'major'

  def testCreateIssueObj(self):
    self.c.options.issuetype = 'story'
    self.c.options.summary = 'Summary'
    self.c.options.description = 'Description'
    self.c.options.priority = 'normal'
    self.c.options.project = 'INFOSYS'
    self.c.options.assignee = 'jirauser'
    self.c.options.components = 'csa'
    self.c.options.fixVersions = '10033'
    self.c.get_priorities()
    i = self.c.create_issue_obj('story',defaults=True)
    desired = {
     'environment': '',
     'duedate': '',
     'labels': [],
     'assignee': {'name':'jirauser'},
     'components': [{'id': '10111'}],
     'versions': [{'id': None}],
     'parent': {'key':None},
     'description': 'Description',
     'fixVersions': [{'id': '10033'}],
     'priority': {'id':'6'},
     'project': {'id':'10001'},
     'timetracking': {'originalEstimate':None},
     'summary': 'Summary',
     'issuetype': {'id':'7'}
    }
    diff = DictDiffer(i.__dict__,desired)
    assert diff.areEqual()

  def testGetIssue(self):
    self.c.get_priorities()
    i = self.c.get_issue('INFOSYS-1')
    assert i['key'] == 'INFOSYS-1'
    assert i['fields']['project']['key'] == 'INFOSYS'

  def testGetIssueLinks(self):
    self.c.get_priorities()
    data = self.c.get_issue_links('INFOSYS-5305')
    #pp.pprint(data)
    assert data[0]['inwardIssue'] is not None

def suite():

  suite = unittest.makeSuite(TestUnit,'test')

  # If we want to add test methods one at a time, then we build up the
  # test suite by hand.
  #suite = unittest.TestSuite()
  #suite.addTest(TestUnit("testLogger"))
  #suite.addTest(TestUnit("testTimeIsValid"))
  #suite.addTest(TestUnit("testFatal"))
  #suite.addTest(TestUnit("testReadConfig"))
  #suite.addTest(TestUnit("testGetProjectId"))
  #suite.addTest(TestUnit("testGetSession"))
  #suite.addTest(TestUnit("testCheckAuth"))
  #suite.addTest(TestUnit("testGetIssue"))
  #suite.addTest(TestUnit("testGetIssueTypes"))
  #suite.addTest(TestUnit("testGetCustomFields"))
  #suite.addTest(TestUnit("testGetIssueLinks"))
  #suite.addTest(TestUnit("testGetResolutions"))
  #suite.addTest(TestUnit("testGetProjectVersions"))
  #suite.addTest(TestUnit("testGetProjectComponents"))
  #suite.addTest(TestUnit("testGetPriorities"))
  #suite.addTest(TestUnit("testCreateIssueObj"))

  return suite

if __name__ == "__main__":
  #print "Unit tests disabled for now"
  unittest.main(defaultTest="suite")
