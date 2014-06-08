import os

scriptdir = os.path.dirname(os.path.realpath(__file__))

PROGRESS_FILE = '/tmp/sabre_postprocessprogress'
PASSWORDS_FILE = scriptdir + '/../../data/passes.json'
TAR_CONTENTS_FILE = scriptdir + '/../../data/tarcontents.json'
TAR_INCLUDE_IMAGE = scriptdir + '/includeimage.jpg'