
import pprint
import sys
import os
import unittest
import SOAPpy
import xmlrpclib

if os.path.exists("../src/"):
  sys.path.insert(0,"../src/")

import jiraclient

pp = pprint.PrettyPrinter()

class TestUnit(unittest.TestCase):

  def testInspect(self):
    return
    i = jiraclient.Issue()
    l = jiraclient.Issue()
    j = SOAPpy.Types.structType(l)
    k = SOAPpy.Types.typedArrayType([1,2,3])
    i.type = 'foo'
    i.project = 'bar'
    i.project = ['foo','bar']
    j.child = k
    i.child = j
    jiraclient.inspect(i)

  def testLogger(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.logger.info('info')
    c.logger.warn('warn')
    c.logger.error('error')
    c.logger.fatal('fatal')

  def testFatal(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    self.assertRaises(SystemExit,c.fatal)

  def testReadConfig(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc"
    c.read_config()

    assert c.options == {
      'comment': None,
      'fixversions': '10033',
      'assignee': 'user',
      'api': None,
      'file': None,
      'affectsversions': None,
      'epic_theme': 'customfield_10020',
      'jiraurl': 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc',
      'unlink': None,
      'issueID': None,
      'priority': 'normal',
      'use_syslog': False,
      'noop': False,
      'template': None,
      'config': './data/jiraclientrc',
      'description': None,
      'subtask': None,
      'link': None,
      'user': 'user',
      'password': 'password',
      'loglevel': 'INFO',
      'type': 'story',
      'summary': None,
      'project': 'INFOSYS',
      'components': '10002',
      'display': False,
    }

  def testGetProjectId(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc-001"
    c.read_config()

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc'
    c.proxy = xmlrpclib.ServerProxy(jiraurl).jira1
    result = c.get_project_id('INFOSYS')
    assert result == '10001'

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/soap/sharedspace-s1v1?wsdl'
    c.proxy = SOAPpy.WSDL.Proxy(jiraurl)
    result = c.get_project_id('INFOSYS')
    assert result == '10001'

  def testGetIssueTypes(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc-001"
    c.read_config()

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc'
    c.proxy = xmlrpclib.ServerProxy(jiraurl).jira1
    projectID = c.get_project_id('INFOSYS')
    result = c.get_issue_types(projectID)
    assert c.typemap == {'story': '7', 'epic': '6', 'sub-task': '5'}

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/soap/sharedspace-s1v1?wsdl'
    c.proxy = SOAPpy.WSDL.Proxy(jiraurl)
    projectID = c.get_project_id('INFOSYS')
    result = c.get_issue_types(projectID)
    assert c.typemap == {'story': '7', 'epic': '6', 'sub-task': '5'}

  def testGetPriorities(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc-001"
    c.read_config()

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc'
    c.proxy = xmlrpclib.ServerProxy(jiraurl).jira1
    result = c.get_priorities()
    assert c.priorities == {'major': '3', 'normal': '6', 'blocker': '1', 'high': '7', 'critical': '2', 'trivial': '5', 'minor': '4'}

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/soap/sharedspace-s1v1?wsdl'
    c.proxy = SOAPpy.WSDL.Proxy(jiraurl)
    result = c.get_priorities()
    assert c.priorities == {'major': '3', 'normal': '6', 'blocker': '1', 'high': '7', 'critical': '2', 'trivial': '5', 'minor': '4'}

  def testCreateIssueObj(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc-001"
    c.read_config()

    c.options.type = 'story'
    c.options.summary = 'Summary'
    c.options.description = 'Description'
    c.options.priority = 'normal'
    c.options.project = 'INFOSYS'
    c.options.assignee = 'user'
    c.options.components = '10001,10002,10003'
    c.options.fixVersions = '10010,10020,10030'
    c.options.affectsVersions = '10010,10020,10030'

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc'
    c.proxy = xmlrpclib.ServerProxy(jiraurl).jira1
    c.get_priorities()
    i = c.create_issue_obj()
    assert i.__dict__ == {
     'assignee': 'user',
     'components': [{'id': '10001'}, {'id': '10002'}, {'id': '10003'}],
     'description': 'Description',
     'fixVersions': [{'id': '10033'}],
     'priority': '6',
     'project': 'INFOSYS',
     'summary': 'Summary',
     'type': '7'
    }

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/soap/sharedspace-s1v1?wsdl'
    c.proxy = SOAPpy.WSDL.Proxy(jiraurl)
    c.get_priorities()
    i = c.create_issue_obj()
    assert i.__dict__ == {
     'assignee': 'user',
     'components': [{'id': '10001'}, {'id': '10002'}, {'id': '10003'}],
     'description': 'Description',
     'fixVersions': [{'id': '10033'}],
     'priority': '6',
     'project': 'INFOSYS',
     'summary': 'Summary',
     'type': '7'
    }

  def testGetIssue(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc-001"
    c.read_config()

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc'
    c.proxy = xmlrpclib.ServerProxy(jiraurl).jira1
    c.get_priorities()
    i = c.get_issue('INFOSYS-1')
    assert i == {'status': '6', 'project': 'INFOSYS', 'updated': '2010-06-01 08:13:58.406', 'votes': '0', 'components': [{'name': 'Research Computing', 'id': '10003'}], 'reporter': 'mcallawa', 'customFieldValues': [{'values': '', 'customfieldId': 'customfield_10010'}, {'values': '', 'customfieldId': 'customfield_10020'}, {'values': '280000000', 'customfieldId': 'customfield_10001'}], 'resolution': '1', 'created': '2010-03-04 16:07:53.85', 'fixVersions': [{'archived': 'true', 'name': 'Sprint 01: 3/1 - 3/18', 'sequence': '6', 'releaseDate': '2010-03-18 00:00:00.0', 'released': 'true', 'id': '10000'}], 'summary': 'Create a basic JIRA installation', 'priority': '3', 'assignee': 'mcallawa', 'key': 'INFOSYS-1', 'affectsVersions': [], 'type': '7', 'id': '10000', 'description': 'Set up JIRA and begin using it for project tracking.'}

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/soap/sharedspace-s1v1?wsdl'
    c.proxy = SOAPpy.WSDL.Proxy(jiraurl)
    c.get_priorities()
    i = c.get_issue('INFOSYS-1')
    assert i.__class__ is SOAPpy.Types.structType

  def testGetIssueLinks(self):
    c = jiraclient.Jiraclient()
    c.parse_args()
    c.prepare_logger()
    c.options.config = "./data/jiraclientrc-001"
    c.read_config()

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/xmlrpc'
    c.proxy = xmlrpclib.ServerProxy(jiraurl).jira1
    c.get_priorities()
    self.assertRaises(SystemExit,c.get_issue_links,'INFOSYS-565')

    jiraurl = 'https://jira-dev.gsc.wustl.edu/rpc/soap/sharedspace-s1v1?wsdl'
    c.proxy = SOAPpy.WSDL.Proxy(jiraurl)
    c.get_priorities()
    result = c.get_issue_links('INFOSYS-565')
    assert result.__class__ is SOAPpy.Types.typedArrayType
    for item in result:
      assert item.__class__ is SOAPpy.Types.structType

  def testCallAPI(self):
     print "start"


def suite():

  suite = unittest.makeSuite(TestUnit,'test')

  # If we want to add test methods one at a time, then we build up the
  # test suite by hand.
  #suite = unittest.TestSuite()
  #suite.addTest(TestUnit("testGetIssueLinks"))

  return suite

if __name__ == "__main__":

  unittest.main(defaultTest="suite")
