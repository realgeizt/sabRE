sabRE
=====
sabRE is a frontend to control SABnzbd, it enables you to share access to your instance of SABnzbd using the SABnzbd API.
* Users can enqueue NZB files or URLs containing a NZB file
* Users can supply passwords for extraction of RAR archives
* sabRE provides an overview about what is happening in SABnzbd (queue/history)
* It is configurable whether users can see only their own enqueued downloads or all downloads which makes some kind of user management for SABnzbd possible
* Downloaded files will be put into a tar archive and can then be downloaded by logged in users. Alternatively sabRE can use the user's name as the download's category so you can set up file shares for each user.
* sabRE is coded in CoffeeScript and is run by node.js, the frontend is built using AngularJS

To get the full sabRE experience you need to follow every step mentioned in the "Installation" paragraph.

Installation
------------
* You need a working node.js installation, I prefer installing from sources (it's easy!). Get it at http://nodejs.org/, extract it, go into the extracted directory and run  
```./configure && make && sudo make install```  
If you are using Ubuntu and don't want to install from source, you need to run  
```sudo apt-get install nodejs npm coffeescript```
* Go to the folder where you want to have sabRE installed, to checkout to your home directory do  
```cd ~```
* To checkout sabRE run  
```git clone https://github.com/realgeizt/sabRE.git```
* Change directory to freshly checked out sabRE with  
```cd sabRE```
* Install needed dependencies by running  
```npm install```
* Make run.sh executable by executing  
```chmod +x run.sh```
* Before starting sabRE you might want to edit data/users.json to setup some users. There are two predefined user accounts, the first one is username "user1" with password "pass1". Every user defined there can login and enqueue/download files.
* Launch sabRE with  
```./run.sh ```  
Now complete the setup wizard. After completion run sabRE again and it will startup using the previously configured settings. The URL of the webinterface is ```http://SABRE_SERVER_IP:3000/```.

If everything went okay, sabRE is configured and running now, but you may still need to configure postprocessing options in SABnzbd. sabRE's setup wizard might have done this for you if you already have a folder for postprocessing scripts setup in SABnzbd. Otherwise see the following instructions.

* If you do not use other postprocessing scripts just configure SABnzbd to use sabRE's postprocessing script directory sabnzbd_scripts. You can do so by using the option "Folders"->"Post-Processing Scripts Folder" in the SABnzbd setup.
* If you use other postprocessing scripts you need to put these scripts together with sabRE's scripts into one directory so SABnzbd can use them all. This means you have to copy sabRE's scripts to another directory or copy other scripts to sabRE's script directory (sabnzbd_scripts). Copying other scripts into sabRE's script directory should be no problem, but when you move sabRE's scripts to another directory you have to make sure that the variables PASSWORDS_FILE and TAR_CONTENTS_FILE in settings.py point to the same files as configured in settings.json which is used by sabRE itself, also make sure to copy all .py files, not only postprocess.py.  
When TAR_CONTENTS_FILE in settings.py is incorrect sabRE won't display contents of tar archives containing downloaded files created by the postprocessor, when PASSWORDS_FILE is incorrect sabRE's postprocessor won't be able to unrar password-protected archives.
