#!/usr/bin/python

import glob
import os
import sys
import yaml

import logging, logging.handlers
from optparse import OptionParser,OptionValueError
import ConfigParser

class Application(object):

  def __init__(self):
    # A default logger to stdout
    logger = logging.getLogger()
    handler = logging.StreamHandler()
    logger.handlers = []
    logger.addHandler(handler)
    self.logger = logger

  def error(self,msg=None,fatal=False):
    if fatal:
      self.logger.fatal(msg)
      sys.exit(1)
    else:
      self.logger.error(msg)

  def parse_args(self):
    usage = """%prog [options]"""

    optParser = OptionParser(usage)
    optParser.add_option(
      "-y","--yamlpath",
      action="store",
      dest="yamlpath",
      help="Read configuration from this file",
      default="/etc/puppet/yaml"
    )
    optParser.add_option(
      "-l","--loglevel",
      type="choice",
      choices=["CRITICAL","ERROR","WARNING","INFO","DEBUG"],
      dest="loglevel",
      help="set the log level",
      default="INFO",
    )
    optParser.add_option(
      "-s","--syslog",
      action="store_true",
      dest="use_syslog",
      help="Use syslog",
      default=False,
    )
    (self.options, self.args) = optParser.parse_args()
    if len(self.args) > 1 or len(self.args) == 0:
      self.error("please specify exactly one hostname")
      optParser.print_help()
      sys.exit(1)

  def prepare_logger(self):
    # prepares a logger optionally to use syslog and with a log level
    (use_syslog,loglevel) = (self.options.use_syslog,self.options.loglevel)

    logger = logging.getLogger()
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

  def is_valid(self,manifest,host):
    # if something is wrong with manifest, log an error but
    # return an empty manifest so that the client gets nothing.
    for key in manifest.keys():
      fatal = False
      if host == key:
        fatal = True
      parameters = None
      classes = None
      if 'parameters' not in manifest[key]:
        self.error("manifest for host '%s' is missing 'parameters'" % key,fatal)
      if not isinstance(manifest[key]['parameters'],dict):
        self.error("parameters for host '%s' is %s, but should be <type 'dict'>" % (key,type(manifest[key]['parameters'])),fatal)
      if 'classes' not in manifest[key]:
        self.error("manifest for host '%s' is missing 'classes'" % key,fatal)
      if not isinstance(manifest[key]['classes'],list):
        self.error("classes for host '%s' is %s, but should be <type 'list'>" % (key,type(manifest[key]['classes'])),fatal)
    return True

  def parse(self,host):
    manifest = {}
    for yamlfile in glob.glob( os.path.join( self.options.yamlpath, "*.yaml" )):
      f = open(yamlfile,"r")
      doc = yaml.load(f)
      f.close()
      manifest.update(doc)
    if self.is_valid(manifest,host):
      return manifest
    else:
      return {}

  def run(self):

    self.parse_args()
    self.prepare_logger()

    host = self.args.pop()
    manifest = self.parse(host)
    result = {
      'parameters': {},
      'classes': [],
    }
    if host in manifest.keys():
      self.logger.info("host %s found in %s" % (host,self.options.yamlpath))
      result = manifest.pop(host)
    else:
      self.logger.info("host %s not found in %s" % (host,self.options.yamlpath))

    # The desired YAML representation of the node to stdout
    print yaml.dump(result,
      default_flow_style=False,
      explicit_start=True,
      indent=4
    )

def main():
  A = Application()
  A.run()
  sys.exit(0)

if __name__ == "__main__":
  main()

