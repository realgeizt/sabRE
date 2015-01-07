import os
import subprocess
import sys
import time
import shutil

class flac2mp3:
    def __init__(self, path):
        self.tags = None
        self.path = path
    def decode(self, infile, outfile):
        self.tags = None

        cmd = ['flac', '-d', infile, '-o', outfile]
        try:
            proc = subprocess.Popen(cmd, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except:
            print 'could not execute flac - is it installed?'
            return False
        proc.wait()
        if proc.returncode != 0:
            return False

        self.tags = {'artist': '', 'title': '', 'album': '', 'genre': '', 'track': '0', 'date': ''}

        self.tags['artist'] = self.getflactag(infile, 'ARTIST')
        self.tags['title'] = self.getflactag(infile, 'TITLE')
        self.tags['album'] = self.getflactag(infile, 'ALBUM')
        self.tags['genre'] = self.getflactag(infile, 'GENRE')
        self.tags['track'] = self.getflactag(infile, 'TRACKNUMBER')
        self.tags['date'] = self.getflactag(infile, 'DATE')
        
        return True
    def encodemp3(self, infile, outfile):
        cmd = ['lame', '--preset', 'extreme', '--add-id3v2', '--tt', self.tags['title'], '--tn', self.tags['track'], '--ta', self.tags['artist'], '--tl', self.tags['album'], '--tg', self.tags['genre'], '--ty', self.tags['date'], infile, outfile]
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
        for root, subFolders, files in os.walk(self.path):
            for file in files:
                if os.path.splitext(os.path.basename(file))[1].lower() == '.flac':
                    orgfile = os.path.join(root, file)
                    wavefile = os.path.join(root, os.path.splitext(os.path.basename(file))[0] + '.wav')
                    mp3file = os.path.join(root, os.path.splitext(os.path.basename(file))[0] + '.mp3')
                    if self.decode(orgfile, wavefile):
                        if not self.encodemp3(wavefile, mp3file):
                            print 'error encoding %s' % os.path.splitext(os.path.basename(file))[0] + '.wav'
                            try:
                                os.remove(wavefile)
                            except:
                                pass
                            try:
                                os.remove(mp3file)
                            except:
                                pass
                        else:
                            print 'encoded %s' % file
                            try:
                                os.remove(orgfile)
                            except:
                                pass
                            try:
                                os.remove(wavefile)
                            except:
                                pass
                    else:
                        print 'error decoding %s' % file
                        try:
                            os.remove(wavefile)
                        except:
                            pass
        return True