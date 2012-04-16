
import pprint
import sys
import os
import unittest
import json
import base64

if os.path.exists("./jiraclient/"):
  sys.path.insert(0,"./jiraclient/")

import jiraclient
from restkit import BasicAuth

pp = pprint.PrettyPrinter(depth=4,stream=sys.stdout)

class DictDiffer(object):
    """
    Calculate the difference between two dictionaries as:
    (1) items added
    (2) items removed
    (3) keys same in both but changed values
    (4) keys same in both and unchanged values
    """
    def __init__(self, current_dict, past_dict):
      self.current_dict, self.past_dict = current_dict, past_dict
      self.set_current, self.set_past = set(current_dict.keys()), set(past_dict.keys())
      self.intersect = self.set_current.intersection(self.set_past)
    def added(self):
      return self.set_current - self.intersect
    def removed(self):
      return self.set_past - self.intersect
    def changed(self):
      return set(o for o in self.intersect if self.past_dict[o] != self.current_dict[o])
    def unchanged(self):
      return set(o for o in self.intersect if self.past_dict[o] == self.current_dict[o])
    def areEqual(self):
      ch = self.changed()
      if len(ch) != 0:
        pp.pprint(ch)
        pp.pprint(self.current_dict)
        return False
      return True
    def areEqual(self):
      ch = self.changed()
      if len(ch) != 0:
        pp.pprint(self.current_dict)
        pp.pprint(ch)
        return False
      return True

class TestUnit(unittest.TestCase):

  def setUp(self):
    self.c = jiraclient.Jiraclient()
    self.c.parse_args()
    self.c.options.config = "./test/data/jiraclientrc-001"
    self.c.options.sessionfile = "./test/data/jira-session"
    self.c.options.loglevel = "DEBUG"
    self.c.prepare_logger()
    self.c.read_config()
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
    desired = {
      'comment': None,
      'fixVersions': 'Backlog',
      'assignee': 'jirauser',
      'api': None,
      'file': None,
      'affectsVersions': None,
      'epic_theme': 'customfield_10020',
      'jiraurl': 'https://jira.gsc.wustl.edu',
      'unlink': None,
      'issueID': None,
      'priority': 'normal',
      'use_syslog': False,
      'noop': False,
      'template': None,
      'config': './test/data/jiraclientrc-001',
      'description': None,
      'subtask': None,
      'link': None,
      'user': 'jirauser',
      'loglevel': 'DEBUG',
      'issuetype': 'story',
      'summary': None,
      'project': 'INFOSYS',
      'components': 'CSA',
    }
    diff = DictDiffer(self.c.__dict__,desired)
    assert diff.areEqual()

  def testGetProjectId(self):
    self.c.get_project_id('INFOSYS')
    assert self.c.maps['project'][10001] == 'infosys'

  def testGetSession(self):
    self.c.token = base64.b64encode("%s:%s" % (self.c.options.user, self.c.options.password))
    assert self.c.get_session() is None

  def testCheckAuth(self):
    if os.path.exists(self.c.options.sessionfile):
      os.unlink(self.c.options.sessionfile)

    # Test success
    self.c.check_auth()
    fd = open(self.c.options.sessionfile,"r")
    cookie = fd.read()
    fd.close()
    assert cookie.startswith("JSESSIONID")
    if os.path.exists(self.c.options.sessionfile):
      os.unlink(self.c.options.sessionfile)

    # Test failure
    self.c.options.password = "wrong"
    self.c.token = base64.b64encode("%s:%s" % (self.c.options.user, self.c.options.password))
    self.assertRaises(SystemExit,self.c.check_auth)
    if os.path.exists(self.c.options.sessionfile):
      os.unlink(self.c.options.sessionfile)

    self.setUp()

  def testGetIssueTypes(self):
    response = self.c.get_issue_types('INFOSYS')
    desired = {'bug': 1, 'epic': 6, 'improvement': 4, 'new feature': 2, 'story': 7, 'sub-task': 5, 'task': 3, 'technical task': 8}
    diff = DictDiffer(self.c.maps['issuetype'],desired)
    assert diff.areEqual()

  def testGetResolutions(self):
    response = self.c.get_resolutions()
    desired = {'cannot reproduce': 5, 'complete': 6, 'duplicate': 3, 'fixed': 1, 'incomplete': 4, "won't fix": 2}
    diff = DictDiffer(self.c.maps['issuetype'],desired)
    assert diff.areEqual()

  def testGetProjectVersions(self):
    response = self.c.get_project_versions('INFOSYS')
    assert self.c.maps['versions'][10180] == 'sprint 2012-1: 1/2 - 1/13'

  def testGetProjectComponents(self):
    response = self.c.get_project_components('INFOSYS')
    assert self.c.maps['components'][10111] == 'csa'

  def testGetPriorities(self):
    response = self.c.get_priorities()
    assert self.c.maps['priority'][3] == 'major'

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
    i = self.c.create_issue_obj(defaults=True)
    desired = {
     'assignee': {'name':'jirauser'},
     'components': [{'id': '10111'}],
     'description': 'Description',
     'fixVersions': [{'id': None}],
     'priority': {'id':'6'},
     'project': {'id':'10001'},
     'summary': 'Summary',
     'issuetype': {'id':'7'}
    }
    diff = DictDiffer(i.__dict__,desired)
    assert diff.areEqual()

  def testGetIssue(self):
    self.c.get_priorities()
    i = self.c.get_issue('INFOSYS-1')
    assert i == {'status': '6', 'project': 'INFOSYS', 'updated': '2010-06-01 08:13:58.406', 'votes': '0', 'components': [{'name': 'Research Computing', 'id': '10003'}], 'reporter': 'mcallawa', 'customFieldValues': [{'values': '', 'customfieldId': 'customfield_10010'}, {'values': '', 'customfieldId': 'customfield_10020'}, {'values': '280000000', 'customfieldId': 'customfield_10001'}], 'resolution': '1', 'created': '2010-03-04 16:07:53.85', 'fixVersions': [{'archived': 'true', 'name': 'Sprint 01: 3/1 - 3/18', 'sequence': '6', 'releaseDate': '2010-03-18 00:00:00.0', 'released': 'true', 'id': '10000'}], 'summary': 'Create a basic JIRA installation', 'priority': '3', 'assignee': 'mcallawa', 'key': 'INFOSYS-1', 'affectsVersions': [], 'issuetype': '7', 'id': '10000', 'description': 'Set up JIRA and begin using it for project tracking.'}

  def testGetIssueLinks(self):
    self.c.get_priorities()
    data = self.c.get_issue_links('INFOSYS-5548')
    #pp.pprint(data)
    assert data[0]['inwardIssue'] is not None

def suite():

  #suite = unittest.makeSuite(TestUnit,'test')

  # If we want to add test methods one at a time, then we build up the
  # test suite by hand.
  suite = unittest.TestSuite()
  #suite.addTest(TestUnit("testLogger"))
  #suite.addTest(TestUnit("testTimeIsValid"))
  #suite.addTest(TestUnit("testFatal"))
  #suite.addTest(TestUnit("testReadConfig"))
  #suite.addTest(TestUnit("testGetProjectId"))
  #suite.addTest(TestUnit("testGetSession"))
  suite.addTest(TestUnit("testCheckAuth"))
  #suite.addTest(TestUnit("testGetIssueTypes"))
  #suite.addTest(TestUnit("testGetResolutions"))
  #suite.addTest(TestUnit("testGetIssueLinks"))
  #suite.addTest(TestUnit("testGetProjectVersions"))
  #suite.addTest(TestUnit("testGetProjectComponents"))
  #suite.addTest(TestUnit("testGetPriorities"))
  #suite.addTest(TestUnit("testCreateIssueObj"))

  return suite

if __name__ == "__main__":
  #print "Unit tests disabled for now"
  unittest.main(defaultTest="suite")
