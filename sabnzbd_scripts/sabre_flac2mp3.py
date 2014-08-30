import os
import subprocess
import sys
import time
import shutil

class flac2mp3:
    def __init__(self, path):
        self.tags = []
        self.path = path
        self.wavsubdir = os.path.join(self.path, 'wav')
        self.mp3subdir = os.path.join(self.path, 'mp3')
    def createsubdir(self, filetype):
        try:
            if filetype == 'wav' and not os.path.exists(self.wavsubdir):
                os.mkdir(self.wavsubdir, 0777)
            elif filetype == 'mp3' and not os.path.exists(self.mp3subdir):
                os.mkdir(self.mp3subdir, 0777)
            return True
        except:
            return False
    def decode(self):
        listing = os.listdir(self.path)
        for item in listing:
            if item.endswith('.flac'):
                cmd = ['flac', '-d', os.path.join(self.path, item), '-o', os.path.join(self.wavsubdir, item[:-5])]
                try:
                    proc = subprocess.Popen(cmd, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                except:
                    print 'could not execute flac - is it installed?'
                    return False
                proc.wait()
                if proc.returncode != 0:
                    return False

                obj = {'name': os.path.splitext(item)[0], 'artist': '', 'title': '', 'album': '', 'genre': '', 'track': '0', 'date': ''}

                obj['artist'] = self.getflactag(os.path.join(self.path, item), 'ARTIST')
                obj['title'] = self.getflactag(os.path.join(self.path, item), 'TITLE')
                obj['album'] = self.getflactag(os.path.join(self.path, item), 'ALBUM')
                obj['genre'] = self.getflactag(os.path.join(self.path, item), 'GENRE')
                obj['track'] = self.getflactag(os.path.join(self.path, item), 'TRACKNUMBER')
                obj['date'] = self.getflactag(os.path.join(self.path, item), 'DATE')
                self.tags.append(obj)
        return True
    def encodemp3(self):
        listing = os.listdir(self.wavsubdir)
        for item in listing:
            obj = {'artist': '', 'title': '', 'album': '', 'genre': '', 'track': '0', 'date': ''}
            for o in self.tags:
                if o['name'] == os.path.splitext(item)[0]:
                    obj = o
                    break
            cmd = ['lame', '--preset', 'extreme', '--add-id3v2', '--tt', obj['title'], '--tn', obj['track'], '--ta', obj['artist'], '--tl', obj['album'], '--tg', obj['genre'], '--ty', obj['date'], os.path.join(self.wavsubdir, item), '%s%s' % (os.path.join(self.mp3subdir, item), '.mp3')]
            try:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except:
                print 'could execute lame - is it installed?'
                return False
            out, err = proc.communicate()
            proc.wait()
            if proc.returncode != 0:
                return False
        return True
    def getflactag(self, filename, tag):
        try:
            proc = subprocess.Popen(['metaflac', filename, '--show-tag=' + tag], shell=False, stdout=subprocess.PIPE)
        except:
            print 'could not execute metaflac - is it installed?'
            return ''
        out, err = proc.communicate()
        if proc.returncode == 0:
            pos = out.find('=')
            if pos > -1:
                return out[pos + 1:].strip()
        return ''
    def run(self):
        try:
            if not self.createsubdir('wav'):
                print 'could not create wav dir'
                return False
            if not self.createsubdir('mp3'):
                print 'Could not create mp3 dir'
                return False
            if not self.decode():
                print 'error while decoding flac files'
                return False
            if not self.encodemp3():
                print 'error while encoding mp3 files'
                return False

            # move mp3s to original dir
            listing = os.listdir(self.mp3subdir)
            for item in listing:
                if item.lower().endswith('.mp3'):
                    shutil.move(os.path.join(self.mp3subdir, item), os.path.join(self.path, item))
            # remove flac files
            listing = os.listdir(self.path)
            for item in listing:
                if item.lower().endswith('.flac'):
                    os.remove(os.path.join(self.path, item))
        finally:
            subprocess.Popen(["rm", "-rf", self.wavsubdir, ]).wait()
            subprocess.Popen(["rm", "-rf", self.mp3subdir, ]).wait()
        return True