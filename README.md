sabRE
=====
sabRE is a frontend to control SABnzbd, it enables you to share access to your instance of SABnzbd using the SABnzbd API.
* Users can enqueue NZB files or URLs containing a NZB file
* Users can supply passwords for extraction of RAR archives
* sabRE provides an overview about what is happening in SABnzbd (queue/history)
* It is coded in CoffeeScript and is run by node.js
* The frontend is built using AngularJS

Installation and start
======================
* You need a working node.js installation, I prefer installing from sources. Get it at http://nodejs.org/.
* Go to the directory where you checked out the project to and run "npm install" which installs all dependencies.
* Modify the file "cs_settings/settings.coffee" according to your needs.
* Modify the file "sabnzbd/scripts/settings.py", some values have to match with the values configured in "cs_settings/settings.coffee".
* Modify the file "data/users.json".
* Set SABnzbd postprocessing script directory to "sabnzbd/scripts" or copy everything from "sabnzbd/scripts" to your usual postprocessing directory.
When copying files to another folder make sure that the pathes in "settings.py" are still correct.
* If you want to use an exetrnal source for authentication adjust the file "cs_settings/settings.coffee" at the key remoteAuth.
Usename and password get posted to the defined URL using the variables "username" and "password".
When authentication is successful the remote script should return "ok".
* Run the application by executing run.sh (and hope that everything works...)
* Navigate your browser to "http://HOST_IP:3000/"
* To make it possible for users to download files you need to have sabRE setup behind an apache instance using mod_proxy with enabled mod_xsendfile module.
When a user downloads a file sabRE will check if the user is logged in and let apache send the file using mod_xsendfile. Here is an example apache host configuration:
```xml
<Directory /sabre_downloads>
        Require all granted
</Directory>
<VirtualHost *:80>
        XSendFile on
        ServerName sabre.host.com
        ProxyRequests off
        <Proxy *>
                Order deny,allow
                Allow from all
        </Proxy>
        ProxyPass / http://localhost:3000/
        ProxyPassReverse / http://localhost:3000/
        XSendFilePath /sabre_downloads
</VirtualHost>
