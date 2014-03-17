
import re
# Read the version info from one place.
VERSIONFILE='./jiraclient/__init__.py'
verstrline = open(VERSIONFILE, "rt").read()
VSRE = r"^__version__ = ['\"]([^'\"]*)['\"]"
match = re.search(VSRE, verstrline, re.M)
if match:
    verstr = match.group(1)
else:
    raise RuntimeError("Unable to find version string in %s." % (VERSIONFILE,))

try:
    from setuptools import setup
except ImportError:
    from distutils.core import setup
setup(name='jiraclient',
      version=verstr,
      packages=['jiraclient'],
      scripts=['bin/jiraclient'],
      install_requires=[
          "restkit",
          "PyYAML"
      ],
     )

