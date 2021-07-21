import os


def killme(ui, repo, hooktype, **wkargs):
    os._exit(80)
