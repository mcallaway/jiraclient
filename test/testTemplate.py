
import pprint
import sys
import os
import unittest
from DictDiffer import DictDiffer;

if os.path.exists("./jiraclient/"):
  sys.path.insert(0,"./jiraclient/")

import jiraclient

pp = pprint.PrettyPrinter(depth=4,stream=sys.stdout)

class TestUnit(unittest.TestCase):

  def setUp(self):
    self.c = jiraclient.Jiraclient()
    self.c.parse_args()
    self.c.options.nopost = True
    self.c.options.norcfile = False
    self.c.options.config = "./test/data/jiraclientrc-001"
    self.c.options.sessionfile = "./test/data/jira-session"
    self.c.options.loglevel = "DEBUG"
    self.c.prepare_logger()
    self.c.read_config()
    self.c.options.user = 'jirauser'
    self.c.options.password = 'jirauser'

  def testTemplate000(self):
    self.c.options.template = "./test/data/project-000.yaml"
    self.c.create_issues_from_template()
    desired = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'description': 'Epic description',
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '6'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'summary': 'This is an Epic'
     }
    for got in self.c.issues_created:
      diff = DictDiffer(got,desired)
      assert diff.areEqual()

  def testTemplate001(self):
    self.c.options.template = "./test/data/project-001.yaml"
    self.c.create_issues_from_template()
    desired_epic = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'description': 'Test Epic description',
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '6'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'summary': 'This is a test Epic'
    }
    desired_subtask = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '5'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'parent': {'key': 'NOOP'},
     'summary': 'This is test epic subtask 1',
     'description': 'This is test epic subtask 1 description'
    }
    epic = self.c.issues_created[0]
    diff = DictDiffer(epic,desired_epic)
    assert diff.areEqual()
    subtask = self.c.issues_created[1]
    diff = DictDiffer(subtask,desired_subtask)
    assert diff.areEqual()

  def testTemplate002(self):
    self.c.options.template = "./test/data/project-002.yaml"
    self.c.create_issues_from_template()
    desired_epic = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'customfield_10441': 'The Epic Name',
     'description': 'Epic description',
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '6'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'summary': 'This is an Epic'
    }
    desired_subtask = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '5'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'summary': 'est1 summary',
     'parent': {'key':'NOOP'},
    }
    desired_story = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '7'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'summary': 's1 summary',
     'description': 'story s1 description',
     'timetracking': {'originalEstimate':'1h'},
    }
    desired_story_subtask = {
     'assignee': {'name': 'jirauser'},
     'components': [{'id': '10111'}],
     'customfield_10010': ['NOOP'],
     'fixVersions': [{'id': '10020'}],
     'issuetype': {'id': '5'},
     'priority': {'id': '6'},
     'project': {'id': '10001'},
     'summary': 's1 st1 summary',
     'description': 's1 st1 description',
     'timetracking': {'originalEstimate':'30m'},
     'parent': {'key':'NOOP'},
    }
    epic = self.c.issues_created[0]
    diff = DictDiffer(epic,desired_epic)
    assert diff.areEqual()
    subtask = self.c.issues_created[1]
    diff = DictDiffer(subtask,desired_subtask)
    assert diff.areEqual()
    story = self.c.issues_created[3]
    diff = DictDiffer(story,desired_story)
    assert diff.areEqual()
    subtask = self.c.issues_created[4]
    diff = DictDiffer(subtask,desired_story_subtask)
    assert diff.areEqual()

def suite():
  suite = unittest.makeSuite(TestUnit,'test')
  #suite = unittest.TestSuite()
  #suite.addTest(TestUnit("testTemplate000"))
  #suite.addTest(TestUnit("testTemplate001"))
  #suite.addTest(TestUnit("testTemplate002"))

  return suite

if __name__ == "__main__":
  unittest.main(defaultTest="suite")
