# Introduction #

Sequel Pro is an ideal tool for working with a MySQL Database on Mac OS X Server.

### Setup MySQL on Mac OS X Server 10.6 ###
  1. Open Server Admin
  1. Select the server from the list.
  1. Click Settings in the toolbar
  1. Under the Services tab, tick MySQL and save your changes
  1. In the list of servers, click the triangle to show the list of active services
  1. Select MySQL
  1. If MySQL is running, click Stop MySQL
  1. Set a Root password
  1. Click Start MySQL

### Connecting to MySQL on with Sequel Pro running on the server ###
  1. [Download](http://code.google.com/p/sequel-pro/downloads/list) and install Sequel Pro
  1. Open Sequel Pro
  1. Select the Socket tab
  1. Enter `root` as the username
  1. Enter the root password
  1. Enter `/var/mysql/mysql.sock` as the socket
  1. Click the Connect button

### Connecting to MySQL on a remote machine running Mac OS X Server ###

_The default MySQL configuration for MacOS X Server does not allow remote access to MySQL._

_See the Mac OS X Server documentation for instructions on how to enable remote access._

_Draft steps to enable remote access:_
  1. _In Server Admin in the MySQL service tick "Allow network connections"_
  1. _Connect to MySQL server locally or via SSH_
  1. _Grant users with access privileges from external hosts/IPs_
  1. _Connect from external host/IP_