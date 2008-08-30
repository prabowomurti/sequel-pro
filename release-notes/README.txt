
 README.txt
 release-notes
 
 Created by Matthew Langtree on 2008-08-31.
 Copyright 2008 Abhi Beckert, Matt Langtree, Ben Perry. All rights reserved.

	
Sequel Pro uses a combination of the Sparkle Framework and Appcasting (RSS Application Feed).

The feed URI should remain constant for the life of the project, or at least should be redirected to the 
path of the new .XML feed - if it needs to be updated.

Currently the Appcast feed resides here:
http://sequelpro.com/appcast/app-releases.xml

Any changes to this path before a release (e.g - Sequel Pro 1.0) is made wont be harmful.

To update this path after at least one release of Sequel Pro has been made that contains the Sparkle
"Check for Updates..." Menu Item, you must setup a 301 redirect on the sequelpro.com server in the .htaccess file.

Additionally the "SUFeedURL" key value in the Sequel Pro Info.plist file will need to be updated accordingly.
