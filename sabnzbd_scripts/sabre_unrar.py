import os
import sys
import time
import re
import json
import traceback
from subprocess import Popen, PIPE, STDOUT
from datetime import datetime, timedelta

import sabre_settings as settings

class unrarer:
    # gets passes for rar files to extract
    def getpasses(self):
        try:
            ret = []
            json_data = open(settings.PASSWORDS_FILE, 'r')
            data = json.load(json_data)
            for p in data:
                ret.append(p['pass'])
            json_data.close()
            return ret
        except:
            return []
    # gets percentage of extraction from rar output line
    def getpercent(self, line):
        fn = line
        fn = fn[fn.rfind(' '):].strip()
        if fn.endswith('%'):
            try:
                return int(fn[:len(fn) - 1].strip())
            except:
                return 100
        else:
            return ''
    # gets a collection of rar files belonging together
    def getcollection(self, f):
        ret = []
        
        fsplit = f[1].lower().split('.')
        pattern = ''
        arcname = ''
        if len(fsplit) > 2 and len(fsplit[-2]) > 4 and fsplit[-2][:4] == 'part':
            pattern = '^(.*)\.part(\d+)\.rar$'
            arcname = os.path.splitext(os.path.splitext(os.path.basename(f[1]))[0])[0]
        elif len(fsplit) > 1 and not (len(fsplit[-2]) > 4 and fsplit[-2][:4] == 'part'):
            pattern = '^(.*)\.r(\d+)$'
            arcname = os.path.splitext(os.path.basename(f[1]))[0]
        
        if pattern != '':
            r = re.compile(pattern, re.IGNORECASE)
            
            for root, subFolders, files in os.walk(f[0]):
                for file in files:
                    m = r.search(file)
                    if m and os.path.basename(file) != '' and os.path.basename(file).startswith(arcname):
                        ret.append(file)

            if len(ret) > 0 and not f[1] in ret:
                ret.append(f[1])
        
        return ret
    # tries to extract a rar archive using a supplied password
    def processfile(self, fn, pwd):
        ok = False
        cmd = ['unrar', 'x', '-o-', '-p' + pwd, fn, ]
        lastprogress = -1
        res = 0
        p = Popen(cmd, stdout=PIPE, stderr=STDOUT)
        for line in iter(p.stdout.readline, ''):
            line = line.strip()
            if line.endswith('%'):
                if self.getpercent(line) > lastprogress and self.getpercent(line) > -1:
                    try:
                        f = open(settings.PROGRESS_FILE, 'w')
                        f.write('RAR|' + str(self.getpercent(line)))
                        f.close()
                    except:
                        pass
            else:
                if line != '':
                    if line.find('is not RAR archive') > -1:
                        res = 10001
                    if line.find('Cannot find volume') > -1:
                        res = 10002
                    if line.find('CRC failed') > -1 or line.find('or wrong password') > -1:
                        res = 10000
            if res != 0:
                p.terminate()

        p.wait()
        
        if res >= 10000:
            return res

        if p.returncode == 0:
            return 0
        return 2
    # gets a list of rar files
    def getfiles(self, path):
        res = []
        
        r = re.compile('^(.*)\.part(0*)1\.rar$', re.IGNORECASE)
        r2 = re.compile('^(.*)\.rar$', re.IGNORECASE)
        
        for root, subFolders, files in os.walk(path):
            for file in files:
                if r.search(file) or (r2.search(file) and file.lower().find('.part') == -1):
                    res.append([root, file])
        return res
    # main function
    def run(self, dir):
        self.rootdir = os.getcwd()
        try:
            print 'getting rar files...'
            files = sorted(self.getfiles(dir))
            
            if len(files) == 0:
                print '  no rar files found, no unrar needed'
                return
            
            print 'getting passes...'
            ppp = self.getpasses()
            
            if len(ppp) == 0:
                print '  no passes found, no unrar possible'
                return
                
            for f in files:
                os.chdir(f[0])
                passfound = ''
                onlycrcerrors = True
                notrararchive = False
                volumesmissing = False
                res = -1
                for p in ppp:
                    f2 = f[1]
                    if len(f2) > 40:
                        f2 = f2[:37] + '...'
                    
                    print 'trying pass %s/%s for %s' % (ppp.index(p) + 1, len(ppp), f2)
                    res = self.processfile(f[1], p)
                    if res != 10000:
                        onlycrcerrors = False
                    if res == 10001:
                        notrararchive = True
                        break
                    if res == 10002:
                        volumesmissing = True
                        break
                    if res == 0:
                        collection = self.getcollection(f)
                        for cf in collection:
                            print '  deleting ' + cf
                            try:
                                os.remove(f[0] + '/' + cf)
                            except:
                                print '  error deleting ' + cf
                        passfound = p
                        break
                if passfound != '':
                    print '  pass found, files extracted'
                else:
                    if notrararchive:
                        print '  %s is no rar archive' % (f[1])
                    elif onlycrcerrors:
                        print '  no pass found or broken volumes for %s' % (f[1])
                    elif volumesmissing:
                        print '  volumes missing for %s' % (f[1])
                    else:
                        print '  files already extracted for %s' % (f[1])
        finally:
            os.chdir(self.rootdir)
