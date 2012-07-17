#!/usr/bin/python

import jiraclient
import pprint

pp = pprint.PrettyPrinter(indent=4)

class WorklogReport(object):
    def __init__(self):
        self.client = jiraclient.Jiraclient()
        self.client.setup()

    def run(self):
        issueID = self.client.options.issueID
        uri = 'rest/api/latest/issue/%s' % issueID
        result = self.client.call_api('get',uri)
        for log in result['fields']['worklog']['worklogs']:
          print "%s %s %s" % (issueID,log['author']['name'],log['comment'])

def main():
    A = WorklogReport()
    try:
        A.run()
    except KeyboardInterrupt:
        print "Exiting..."
        return

if __name__ == "__main__":
    main()

