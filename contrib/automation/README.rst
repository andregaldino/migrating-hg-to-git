====================
Mercurial Automation
====================

This directory contains code and utilities for building and testing Mercurial
on remote machines.

The ``automation.py`` Script
============================

``automation.py`` is an executable Python script (requires Python 3.5+)
that serves as a driver to common automation tasks.

When executed, the script will *bootstrap* a virtualenv in
``<source-root>/build/venv-automation`` then re-execute itself using
that virtualenv. So there is no need for the caller to have a virtualenv
explicitly activated. This virtualenv will be populated with various
dependencies (as defined by the ``requirements.txt`` file).

To see what you can do with this script, simply run it::

   $ ./automation.py

Local State
===========

By default, local state required to interact with remote servers is stored
in the ``~/.hgautomation`` directory.

We attempt to limit persistent state to this directory. Even when
performing tasks that may have side-effects, we try to limit those
side-effects so they don't impact the local system. e.g. when we SSH
into a remote machine, we create a temporary directory for the SSH
config so the user's known hosts file isn't updated.

AWS Integration
===============

Various automation tasks integrate with AWS to provide access to
resources such as EC2 instances for generic compute.

This obviously requires an AWS account and credentials to work.

We use the ``boto3`` library for interacting with AWS APIs. We do not employ
any special functionality for telling ``boto3`` where to find AWS credentials. See
https://boto3.amazonaws.com/v1/documentation/api/latest/guide/configuration.html
for how ``boto3`` works. Once you have configured your environment such
that ``boto3`` can find credentials, interaction with AWS should *just work*.

.. hint::

   Typically you have a ``~/.aws/credentials`` file containing AWS
   credentials. If you manage multiple credentials, you can override which
   *profile* to use at run-time by setting the ``AWS_PROFILE`` environment
   variable.

Resource Management
-------------------

Depending on the task being performed, various AWS services will be accessed.
This of course requires AWS credentials with permissions to access these
services.

The following AWS services can be accessed by automation tasks:

* EC2
* IAM
* Simple Systems Manager (SSM)

Various resources will also be created as part of performing various tasks.
This also requires various permissions.

The following AWS resources can be created by automation tasks:

* EC2 key pairs
* EC2 security groups
* EC2 instances
* IAM roles and instance profiles
* SSM command invocations

When possible, we prefix resource names with ``hg-`` so they can easily
be identified as belonging to Mercurial.

.. important::

   We currently assume that AWS accounts utilized by *us* are single
   tenancy. Attempts to have discrete users of ``automation.py`` (including
   sharing credentials across machines) using the same AWS account can result
   in them interfering with each other and things breaking.

Cost of Operation
-----------------

``automation.py`` tries to be frugal with regards to utilization of remote
resources. Persistent remote resources are minimized in order to keep costs
in check. For example, EC2 instances are often ephemeral and only live as long
as the operation being performed.

Under normal operation, recurring costs are limited to:

* Storage costs for AMI / EBS snapshots. This should be just a few pennies
  per month.

When running EC2 instances, you'll be billed accordingly. By default, we
use *small* instances, like ``t3.medium``. This instance type costs ~$0.07 per
hour.

.. note::

   When running Windows EC2 instances, AWS bills at the full hourly cost, even
   if the instance doesn't run for a full hour (per-second billing doesn't
   apply to Windows AMIs).

Managing Remote Resources
-------------------------

Occassionally, there may be an error purging a temporary resource. Or you
may wish to forcefully purge remote state. Commands can be invoked to manually
purge remote resources.

To terminate all EC2 instances that we manage::

   $ automation.py terminate-ec2-instances

To purge all EC2 resources that we manage::

   $ automation.py purge-ec2-resources
