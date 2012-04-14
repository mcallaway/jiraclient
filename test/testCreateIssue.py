
import pprint
import sys
import os
import unittest
import json
import base64

if os.path.exists("./src/"):
  sys.path.insert(0,"./src/")

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

  def testCreateSimpleIssue(self):
    self.c.options.project = "INFOSYS"
    issue = self.c.create_issue_obj()
    got = issue.__dict__
    desired = {
      'assignee': {'name': None},
      'components': [{'id': None}],
      'description': '',
      'duedate': '',
      'environment': '',
      'fixVersions': [{'id': None}],
      'issuetype': {'id': None},
      'labels': [],
      'priority': {'id': None},
      'project': {'id': 10001},
      'security': {'id': None},
      'summary': '',
      'timetracking': {'originalEstimate': None, 'remainingEstimate': None},
      'versions': [{'id': None}],
    }
    diff = DictDiffer(got,desired)
    ch = diff.changed()
    if len(ch) != 0:
      pp.pprint(ch)
      pp.pprint(issue.__dict__)
    assert len(ch) == 0

  def testCreateIssueObj(self):
    # command line or rc file input
    self.c.options.assignee = 'jirauser'
    self.c.options.components = 'csa'
    self.c.options.description = 'description'
    self.c.options.duedate = '2012-04-13'
    self.c.options.environment = 'environment'
    self.c.options.fixVersions = 'Backlog'
    self.c.options.issuetype = 'task'
    self.c.options.labels = 'change,maintenance'
    self.c.options.priority = 'minor'
    self.c.options.project = 'infosys'
    #self.c.options.security = ''
    self.c.options.summary = 'summary'
    #self.c.options.timetracking = '2h'
    self.c.options.versions = 'Ideas'
    self.c.options.epic_theme = 'INFOSYS-100'

    issue = self.c.create_issue_obj()
    got = issue.__dict__
    desired = {
      'assignee': {'name': 'jirauser'},
      'components': [{'id': [10111]}],
      'description': 'description',
      'duedate': '2012-04-13',
      'environment': 'environment',
      'fixVersions': [{'id': [10020]}],
      'issuetype': {'id': [3]},
      'labels': ['change', 'maintenance'],
      'priority': {'id': [4]},
      'project': {'id': [10001]},
      'security': {'id': None},
      'summary': 'summary',
      'timetracking': {'originalEstimate': None, 'remainingEstimate': None},
      'versions': [{'id': [10080]}],
      'customfield_10010': 'INFOSYS-100'
    }
    diff = DictDiffer(got,desired)
    ch = diff.changed()
    if len(ch) != 0:
      pp.pprint(ch)
    assert len(ch) == 0

def suite():

  #suite = unittest.makeSuite(TestUnit,'test')

  # If we want to add test methods one at a time, then we build up the
  # test suite by hand.
  suite = unittest.TestSuite()
  suite.addTest(TestUnit("testCreateSimpleIssue"))
  #suite.addTest(TestUnit("testCreateIssueObj"))

  return suite

if __name__ == "__main__":
  unittest.main(defaultTest="suite")
