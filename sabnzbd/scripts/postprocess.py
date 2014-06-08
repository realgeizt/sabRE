#!/usr/bin/python2.7
import sys
import os
import subprocess
import time
import threading
import signal
import json
import shutil
import random, string
import traceback

import settings
from unrar import unrarer

# this thread sends SIGUSR1 to tar so that it outputs its progress
class SignalSender(threading.Thread): 
    def __init__(self): 
        threading.Thread.__init__(self)
        self.pid = -1
    def run(self): 
        while True:
            time.sleep(1)
            try:
                os.kill(self.pid, signal.SIGUSR1)
            except:
                break

# main class
class PostProcessor:
    def __init__(self):
        pass
    # gets the size of a directory recursively
    def getsize(self, startpath = '.'):
        total_size = 0
        for dirpath, dirnames, filenames in os.walk(startpath):
            for f in filenames:
                fp = os.path.join(dirpath, f)
                total_size += os.path.getsize(fp)
        return total_size
    # build a random 'word'
    def randomword(self, length):
       return ''.join(random.choice(string.lowercase) for i in range(length))
    # gets a list of files recursively
    def getfiles(self, startpath = '.'):
        res = []
        for dirpath, dirnames, filenames in os.walk(startpath):
            for f in filenames:
                res.append(f)
        return res
    # writes unrar/tar progress to file that is read by sabRE
    def writeprogress(self, type, progress):
        try:
            f = open(settings.PROGRESS_FILE, 'w')
            f.write(type.upper() + '|' + str(progress))
            f.close()
        except Exception, e:
            print traceback.format_exc(e)
    def unrar(self, dir):
        try:
            unrarer().run(download_final_dir)
            return True
        except Exception, e:
            print traceback.format_exc(e)
        return False
    def writecontents(self):
        try:
            json_data = open(settings.TAR_CONTENTS_FILE, 'r')
            data = json.load(json_data)
            json_data.close()
        except:
            data = []
        exists = False
        for e in data:
            if e['filename'] == self.downloadFile + '.tar':
                exists = True
                break
        if not exists:
            data.append({'filename': self.downloadFile + '.tar', 'files': self.getfiles(self.downloadDir + self.downloadFile)})
        with open(settings.TAR_CONTENTS_FILE, 'w') as outfile:
          json.dump(data, outfile)
    def run(self):
        # get path to downloaded files
        downloadDir = sys.argv[1]
        
        if not os.path.exists(downloadDir):
            print 'directory does not exist'
            return 1

        # this should be the root directory where sabnzbd downloads go
        self.downloadFile = os.path.split(downloadDir)[1]
        self.downloadDir = os.path.split(downloadDir)[0]
        if len(self.downloadDir) > 1:
            self.downloadDir += '/'
        
        print 'processing "%s" in directory "%s"' % (self.downloadFile, self.downloadDir)
        
        # unrar everything
        self.writeprogress('rar', -1)
        try:
            unrarer().run(self.downloadDir + self.downloadFile)
        except Exception, e:
            print traceback.format_exc(e)
        
        # change directory
        os.chdir(self.downloadDir)

        # delete the tar file before creating it later
        try:
            os.remove(self.downloadFile + '.tar')
        except:
            pass

        size = self.getsize(self.downloadDir + self.downloadFile)
        rndImgFile = self.randomword(10) + '.jpg'

        # write contents of soon created tar file to file read by sabRE
        self.writecontents()

        try:
            shutil.copy(settings.TAR_INCLUDE_IMAGE, self.downloadDir + self.downloadFile + '/' + rndImgFile)
        except:
            pass

        # tar all downloaded files
        self.writeprogress('tar', 0)
        proc = subprocess.Popen(["tar", "cvf", self.downloadFile + '.tar', "--totals=SIGUSR1", self.downloadFile], stderr=subprocess.PIPE)

        # start the thread that sends signals to tar
        thread = SignalSender() 
        thread.pid = proc.pid
        thread.start()
        
        # now watch the output of tar and write it to the progressfile read by sabRE
        lastpercent = 0
        for line in iter(proc.stderr.readline, ''):
            l = line.split(' ')
            try:
                percent = int((float(l[3]) / size) * 100)
                if percent > lastpercent and percent > -1:
                    self.writeprogress('tar', percent)
                    lastpercent = percent
            except Exception, e:
                return 1
        proc.wait()

        # allow access to everybody...
        try:
            subprocess.Popen(["chmod", "666", self.downloadFile + '.tar', ])
        except Exception, e:
            print traceback.format_exc(e)

        # kick progressfile
        try:
            os.remove(settings.PROGRESS_FILE)
        except:
            pass

        # remove the files that are now in the tar archive
        proc2 = subprocess.Popen(['rm', '-rf', self.downloadDir + self.downloadFile], stdout=subprocess.PIPE)
        proc2.wait()

        if proc.returncode != 0:
            return 1
        else:
            return 0


# check arguments
if len(sys.argv) < 2: #8:
    print 'args missing...'
    sys.exit(1)

sys.exit(PostProcessor().run())
