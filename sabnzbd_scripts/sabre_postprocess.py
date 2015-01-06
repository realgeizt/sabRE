#!/usr/bin/env python2.7

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

import sabre_settings as settings
from sabre_unrar import unrarer
from sabre_flac2mp3 import flac2mp3

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
                res.append(f.decode('utf-8', 'ignore'))
        return res
    # writes unrar/tar progress to file that is read by sabRE
    def writeprogress(self, type, progress):
        try:
            f = open(settings.PROGRESS_FILE, 'w')
            f.write(type.upper() + '|' + str(progress))
            f.close()
            proc2 = subprocess.Popen(["chmod", "666", settings.PROGRESS_FILE, ])
            proc2.wait()
        except Exception, e:
            print traceback.format_exc(e)
    # renames potentially dangerous files in order to protect noobs :)
    def renameexecutables(self, startpath = '.'):
        print 'renaming executables...'
        badextensions = ['.com', '.exe', '.bat', '.cmd', '.vbs', '.vbe', '.wsh', '.wsf', '.scr', '.msi']
        for dirpath, dirnames, filenames in os.walk(startpath):
            for f in filenames:
                f = f.decode('utf-8', 'ignore')
                base = os.path.splitext(f)[0]
                ext = os.path.splitext(f)[1]
                if len(base) > 0 and len(ext) > 0 and ext.lower() in badextensions:
                    try:
                        newname = base + ext + '_'
                        print 'renaming executable "%s" to "%s"' % (f.encode('ascii', 'replace'), newname.encode('ascii', 'replace'))
                        os.rename(dirpath + '/' + f, dirpath + '/' + newname)
                    except:
                        print 'could not rename executable "%s"' % f.encode('ascii', 'replace')
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
        proc2 = subprocess.Popen(["chmod", "666", settings.TAR_CONTENTS_FILE, ])
        proc2.wait()
    def getusernzb(self, nzb, prop):
        try:
            json_data = open(settings.USER_NZBS_FILE, 'r')
            try:
                data = json.load(json_data)
                for val in data:
                    try:
                        if val['nzb'] == nzb:
                            return val[prop]
                    except:
                        pass
            except:
                pass
            json_data.close()
        except:
            pass
        return None
    def run(self):
        error = False
        
        # get path to downloaded files
        downloadDir = sys.argv[1]
        originalName = sys.argv[3]
        if not os.path.exists(downloadDir):
            print 'directory "%s" does not exist' % downloadDir
            return 1

        # this should be the root directory where sabnzbd downloads go
        self.downloadFile = os.path.split(downloadDir)[1]
        self.downloadDir = os.path.split(downloadDir)[0]
        if len(self.downloadDir) > 1:
            self.downloadDir += '/'
        
        print 'processing "%s" in directory "%s"' % (self.downloadFile, self.downloadDir)
        
        print 'starting unrar'
        
        # unrar everything
        self.writeprogress('rar', -1)
        try:
            unrarer().run(self.downloadDir + self.downloadFile)
        except Exception, e:
            print 'exception in unrar: ' + traceback.format_exc(e)
            error = True
        
        # change directory
        os.chdir(self.downloadDir)
        
        # delete the tar file before creating it later
        try:
            os.remove(self.downloadFile + '.tar')
        except:
            pass
        
        size = self.getsize(self.downloadDir + self.downloadFile)
        rndImgFile = self.randomword(10) + '.jpg'
        
        # if desired rename windows executables
        if settings.RENAME_WINDOWS_EXECUTABLES:
            self.renameexecutables(self.downloadDir + self.downloadFile)
        
        # if wanted convert flac to mp3
        if self.getusernzb(originalName, 'flac2mp3'):
            print 'converting flac to mp3'
            flac2mp3(self.downloadDir + self.downloadFile).run()
        
        # write contents of soon created tar file to file read by sabRE
        print 'modifying tar content file'
        try:
            self.writecontents()
        except Exception, e:
            print 'exception in writecontents(): ' + traceback.format_exc(e)
            error = True

        try:
            shutil.copy(settings.TAR_INCLUDE_IMAGE, self.downloadDir + self.downloadFile + '/' + rndImgFile)
        except:
            pass

        # tar all downloaded files
        cmd = ["tar", "cvf", self.downloadFile + '.tar', "--totals=SIGUSR1", self.downloadFile]
        print 'running tar: ' + str(cmd)
        self.writeprogress('tar', 0)
        proc = subprocess.Popen(cmd, stderr=subprocess.PIPE)

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
                print traceback.format_exc(e)
                return 1
        proc.wait()
        if proc.returncode != 0:
            error = True

        # allow access to everybody...
        try:
            proc2 = subprocess.Popen(["chmod", "666", self.downloadFile + '.tar', ])
            proc2.wait()
        except Exception, e:
            print traceback.format_exc(e)

        # kick progressfile
        try:
            os.remove(settings.PROGRESS_FILE)
        except:
            pass

        # remove the files that are now in the tar archive
        print 'deleting original download'
        proc2 = subprocess.Popen(['rm', '-rf', self.downloadDir + self.downloadFile], stdout=subprocess.PIPE)
        proc2.wait()

        if error:
            print 'completed with problems. check script output.'
            return 1
        else:
            print 'completed successfully'
            return 0

# check arguments
if len(sys.argv) < 4:
    print 'args missing...'
    sys.exit(1)

sys.exit(PostProcessor().run())