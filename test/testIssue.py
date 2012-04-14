
import pprint
import sys
import os
import logging
import unittest

if os.path.exists("./src/"):
  sys.path.insert(0,"./src/")

import jiraclient

pp = pprint.PrettyPrinter(depth=4,stream=sys.stdout)

class TestUnit(unittest.TestCase):

  def setUp(self):
    self.i = jiraclient.Issue()

  def testIssue(self):
    self.i.update('summary','This is a summary')
    self.i.update('timetracking',{ 'originalEstimate':'2h' })
    self.i.update('versions',[{'id':10080}])
    pp.pprint(self.i.summary)
    pp.pprint(self.i)

def suite():
  return unittest.makeSuite(TestUnit,'test')

if __name__ == "__main__":
  unittest.main(defaultTest="suite")
