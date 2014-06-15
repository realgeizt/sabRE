import os

scriptdir = os.path.dirname(os.path.realpath(__file__))

TAR_INCLUDE_IMAGE = scriptdir + '/includeimage.jpg'

# WARNING: everything configured from here on has to point to the
#          same file as in sabRE's configuration (settings.json).
PROGRESS_FILE = '/tmp/sabre_postprocessprogress'
PASSWORDS_FILE = scriptdir + '/../../data/passes.json'
TAR_CONTENTS_FILE = scriptdir + '/../../data/tarcontents.json'
