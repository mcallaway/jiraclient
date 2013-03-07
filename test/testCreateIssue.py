
import pprint
import sys
import os
import unittest

if os.path.exists("./jiraclient/"):
  sys.path.insert(0,"./jiraclient/")

from DictDiffer import DictDiffer
import jiraclient

pp = pprint.PrettyPrinter(depth=4,stream=sys.stdout)

class TestUnit(unittest.TestCase):

  def setUp(self):
    self.c = jiraclient.Jiraclient()
    self.c.parse_args()
    self.c.options.config = "./test/data/jiraclientrc-001"
    self.c.options.sessionfile = "./test/data/jira-session"
    self.c.options.loglevel = "DEBUG"
    self.c.prepare_logger()
    self.c.read_config()
    self.c.options.noop = True
    self.c.options.user = 'jirauser'
    self.c.options.password = 'jirauser'

  def testUpdateIssueObj(self):
    self.c.options.project = "INFOSYS"
    issue = self.c.create_issue_obj('task')
    issue = self.c.update_issue_obj(issue,'components','CSA')
    issue = self.c.update_issue_obj(issue,'labels','change')
    issue = self.c.update_issue_obj(issue,'assignee','jirauser')
    issue = self.c.update_issue_obj(issue,'summary','summary')

  def testCreateSimpleIssue(self):
    self.c.options.project = "INFOSYS"
    issue = self.c.create_issue_obj('task')
    got = issue.__dict__
    desired = {
      'assignee': {'name': None},
      'components': [{'id': None}],
      'description': '',
      'duedate': '',
      'environment': '',
      'fixVersions': [{'id': None}],
      'issuetype': {'id': '3'},
      'labels': [],
      'priority': {'id': None},
      'project': {'id': '00'},
      'parent': {'key': None},
      'summary': '',
      'timetracking': {'originalEstimate': None},
      'versions': [{'id': None}],
    }
    diff = DictDiffer(got,desired)
    assert diff.areEqual()

  def testCreateIssueObj(self):
    # command line or rc file input
    self.c.options.noop = False
    self.c.options.assignee = 'jirauser'
    self.c.options.components = 'csa'
    self.c.options.description = 'description'
    self.c.options.duedate = '2012-04-13'
    self.c.options.environment = 'environment'
    self.c.options.fixVersions = 'Backlog'
    self.c.options.issuetype = 'task'
    self.c.options.labels = 'change,maintenance'
    self.c.options.priority = 'minor'
    self.c.options.project = 'INFOSYS'
    self.c.options.summary = 'summary'
    #self.c.options.timetracking = '2h'
    self.c.options.versions = 'Ideas'
    self.c.options.epic_theme = 'INFOSYS-100'

    issue = self.c.create_issue_obj('task')
    got = issue.__dict__
    desired = {
      'assignee': {'name': 'jirauser'},
      'components': [{'id': '10111'}],
      'description': 'description',
      'duedate': '2012-04-13',
      'environment': 'environment',
      'fixVersions': [{'id': '10020'}],
      'issuetype': {'id': '3'},
      'labels': ['change', 'maintenance'],
      'priority': {'id': '4'},
      'project': {'id': '10001'},
      'summary': 'summary',
      'parent': {'key': None},
      'timetracking': {'originalEstimate': None},
      'versions': [{'id': '10080'}],
      'customfield_10010': ['INFOSYS-100'],
    }
    diff = DictDiffer(got,desired)
    assert diff.areEqual()

def suite():

  suite = unittest.makeSuite(TestUnit,'test')

  # If we want to add test methods one at a time, then we build up the
  # test suite by hand.
  #suite = unittest.TestSuite()
  #suite.addTest(TestUnit("testUpdateIssueObj"))
  #suite.addTest(TestUnit("testCreateSimpleIssue"))
  #suite.addTest(TestUnit("testCreateIssueObj"))

  return suite

if __name__ == "__main__":
  unittest.main(defaultTest="suite")
