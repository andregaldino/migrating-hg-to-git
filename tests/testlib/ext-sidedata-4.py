# coding: utf8
# ext-sidedata-4.py - small extension to test (differently still) the sidedata
# logic
#
# Simulates a server for a complex sidedata exchange.
#
# Copyright 2021 Raphaël Gomès <rgomes@octobus.net>
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2 or any later version.


from mercurial.revlogutils import sidedata


def reposetup(ui, repo):
    repo.register_wanted_sidedata(sidedata.SD_TEST2)
    repo.register_wanted_sidedata(sidedata.SD_TEST3)
