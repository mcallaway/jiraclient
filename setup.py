try:
    from setuptools import setup
except ImportError:
    from distutils.core import setup
setup(name='jiraclient',
      packages=['jiraclient'],
      scripts=['bin/jiraclient'],
      install_requires=[
          "restkit"
      ],
     )

