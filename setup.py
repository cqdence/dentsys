#!/usr/bin/env python
"""
    setup
    ~~~~~~~~~~~~~~

    pyznap installation using setuptools.

    :copyright: (c) 2018-2019 by Yannick Boetzel.
    :license: GPLv3, see LICENSE for more details.
"""
# Modified by Dentsys (November 2025): Renamed console script entry point.

import os
import re
from setuptools import setup


DIRNAME = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(DIRNAME, 'README.md'), 'r') as file:
    readme = file.read()

with open(os.path.join(DIRNAME, 'pyznap/__init__.py'), 'r') as file:
    version = re.search(r'__version__ = \'(.*?)\'', file.read()).group(1)

setup(
    name='pyznap',
    version=version,
    description='Dentsys standardized ZFS snapshot tool',
    long_description=readme,
    long_description_content_type="text/markdown",
    keywords='zfs snapshot backup',
    url='https://github.com/cqdence/dentsys',
    author='Dentsys',
    author_email='support@gpconnectivity.com',
    license='GPLv3',
    packages=['dentsys'],
    include_package_data=True,
    python_requires='>=3.5',
    extras_require={
        'dev': [
            'pytest',
            'pytest-dependency',
            'pytest-runner',
            'paramiko>=2.4.2',
        ]
    },
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Environment :: Console',
        'Intended Audience :: End Users/Desktop',
        'License :: OSI Approved :: GNU General Public License v3 (GPLv3)',
        'Operating System :: Unix',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.5',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Topic :: System :: Archiving :: Backup',
        'Topic :: System :: Filesystems',
    ],
    entry_points = {
        'console_scripts': ['dentsys=pyznap.main:main'],
    },
    zip_safe=False
)
