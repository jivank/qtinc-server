# qtinc-server
This is experimental software, please use at your own risk.

This was a quick personal project to learn Nim and automate setting up tinc networks. Please let me know if you have any suggestions and I am always open to pull requests.

Tested Platforms:
- Windows
- MacOS
- Linux

# Implementation

I take a fairly simple approach. Each network is has its own /24 subnet such as 10.0.0.0. With the current implementation you may only have 254 hosts per network and currently only 254 networks. The qtinc server will give new clients an unused IP address based off current IPs found in the pending and hosts folder.

# Setup
Requirements:
- Nim
- Nimble
- Jester

After installing Nim and Nimble, you may install Jester with the following command:
`nimble install jester`

Now compile the binary with:
`nim c qtincserver`

Edit qtinc.conf and edit `tincHome` to the path where your tinc network folders exist (e.g /etc/tinc or /opt/local/etc/tinc or C:\Program Files\tinc)

Run the binary qtincserver
`./qtincserver`

It will use port 5000.

Using the qtinc-cli tool, you may add and join networks.

# Usage
When clients join, they will be added to a pending folder when requireAuth is enabled in qtinc.conf. 
You may add additional trusted IPs separated by comma (e.g `trusted = 127.0.0.1,10.0.0.1`) in qtinc.conf.

You can view clients who require approval with:

`curl localhost:5000/networks/<network>/pending`

Use the following command to approve a client:

`curl localhost:5000/networks/<network>/pending/<client_name>/approve`

# Roadmap
1. Merge client and server into one executable
2. Develop UI
3. Allow custom port


# Known Issues
- It is possible to get spammed by authorization requests where clients can no longer join as qtinc will not be able to issue a new IP address.
