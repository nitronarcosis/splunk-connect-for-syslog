# Install podman

Refer to [Installation](https://podman.io/getting-started/installation)

NOTE: [READ FIRST (IPv4 forwarding)](./getting-started-runtime-configuration.md#ipv4-forwarding)

# Initial Setup

* IMPORTANT:  Always use the _latest_ unit file (below) with the current release.  By default, the latest container is
automatically downloaded at each restart.  Therefore, make it a habit to check back here regularly to be sure any changes
that may have been made to the template unit file below (e.g. suggested mount points) are incorporated in production prior
to relaunching via systemd.

* Create the systemd unit file `/lib/systemd/system/sc4s.service` based on the following template:
#### Unit file
```ini
--8<--- "docs/resources/podman/sc4s.service"
```

* Execute the following command to create a local volume that will contain the disk buffer files in the event of a communication
failure to the upstream destination(s).  This will also be used to keep track of the state of syslog-ng between restarts, and in
particular the state of the disk buffer.  This is a required step.

```
sudo podman volume create splunk-sc4s-var
```

* NOTE:  Be sure to account for disk space requirements for the podman volume created above. This volume is located in
`/var/lib/containers/storage/volumes/` and could grow significantly if there is an extended outage to the SC4S destinations
(typically HEC endpoints). See the "SC4S Disk Buffer Configuration" section on the Configuration page for more info.

* Create subdirectories `/opt/sc4s/local` `/opt/sc4s/archive` `/opt/sc4s/tls` 

Create a file named `/opt/sc4s/env_file` and add the following environment variables and values:

```dotenv
--8<--- "docs/resources/env_file"
```

* Update `SC4S_DEST_SPLUNK_HEC_DEFAULT_URL` and `SC4S_DEST_SPLUNK_HEC_DEFAULT_TOKEN` to reflect the correct values for your environment.  Do _not_ configure HEC
Acknowledgement when deploying the HEC token on the Splunk side; the underlying syslog-ng http destination does not support this
feature.  Moreover, HEC Ack would significantly degrade performance for streaming data such as syslog.

* The default number of `SC4S_DEST_SPLUNK_HEC_WORKERS` is 10. Consult the community if you feel the number of workers (threads) should
deviate from this.

* NOTE:  Splunk Connect for Syslog defaults to secure configurations.  If you are not using trusted SSL certificates, be sure to
uncomment the last line in the example above.

For more information about configuration refer to [Docker and Podman basic configurations](./getting-started-runtime-configuration.md#docker-and-podman-basic-configurations)
and [detailed configuration](../configuration.md).

# Configure SC4S for systemd and start SC4S

```bash
sudo systemctl daemon-reload
sudo systemctl enable sc4s
sudo systemctl start sc4s
```
## Restart SC4S

```bash
sudo systemctl restart sc4s
```

If changes were made to the configuration Unit file above (e.g. to configure with dedicated ports), you must first stop SC4S and re-run
the systemd configuration commands:

```bash
sudo systemctl stop sc4s
sudo systemctl daemon-reload 
sudo systemctl enable sc4s
sudo systemctl start sc4s
```

## Stop SC4S

```bash
sudo systemctl stop sc4s
```

# Verify Proper Operation

SC4S has a number of "preflight" checks to ensure that the container starts properly and that the syntax of the underlying syslog-ng
configuration is correct.  After this step completes, to verify SC4S is properly communicating with Splunk,
execute the following search in Splunk:

```ini
index=* sourcetype=sc4s:events "starting up"
```

This should yield an event similar to the following:

```ini
syslog-ng starting up; version='3.28.1'
```

When the startup process proceeds normally (without syntax errors). If you do not see this,
follow the steps below before proceeding to deeper-level troubleshooting:

* Check to see that the URL, token, and TLS/SSL settings are correct, and that the appropriate firewall ports are open (8088 or 443).
* Check to see that the proper indexes are created in Splunk, and that the token has access to them.
* Ensure the proper operation of the load balancer if used.
* Lastly, execute the following command to check the sc4s startup process running in the container.

```bash
docker logs SC4S
```

You should see events similar to those below in the output:

```ini
syslog-ng checking config
sc4s version=v1.36.0
starting goss
starting syslog-ng
```

If you do not see the output above, proceed to the ["Troubleshoot sc4s server"](../troubleshooting/troubleshoot_SC4S_server.md)
and ["Troubleshoot resources"](../troubleshooting/troubleshoot_resources.md) sections for more detailed information.

# SC4S non-root operation

To operate SC4S as a user other than root, follow the instructions above, with these modifications:

## Prepare sc4s user

Create a non-root user in which to run SC4S and prepare podman for non-root operation:

```bash
sudo useradd -m -d /home/sc4s -s /bin/bash sc4s
sudo su - sc4s
mkdir -p /home/sc4s/local
mkdir -p /home/sc4s/archive
mkdir -p /home/sc4s/tls
podman system migrate
```

## Initial Setup

NOTE:  Be sure to execute all instructions below as the SC4S user created above except of changes to the unit file,
which requires sudo access.

NOTE2: Using non-root prevents the use of standard ports 514 and 601 many device can not alter their destination port this is not
a valid configuration for general use, and may only be appropriate for cases where accepting syslog from the public internet can not
be avoided.

Make the following changes to the unit file(s) configured in the main section:

* Add the name of the user created above immediately after the Service declaration, as shown in the snippet below:

```
[Service]
User=sc4s
```

* Add the following to the env_file

```
SC4S_LISTEN_DEFAULT_TCP_PORT=${SC4S_LISTEN_DEFAULT_TCP_PORT=8514}
SC4S_LISTEN_DEFAULT_UDP_PORT=${SC4S_LISTEN_DEFAULT_UDP_PORT=8514}
SC4S_LISTEN_DEFAULT_RFC5426_PORT=${SC4S_LISTEN_DEFAULT_RFC5426_PORT=8601}
SC4S_LISTEN_DEFAULT_RFC6587_PORT=${SC4S_LISTEN_DEFAULT_RFC6587_PORT=8601}
```

* Replace all references to `/opt/sc4s` in the "Environment" declarations with `/home/sc4s`.  Make sure _not_ to change the
right-hand-side of the mount. For example:

```
Environment="SC4S_LOCAL_CONFIG_MOUNT=-v /home/sc4s/local:/etc/syslog-ng/conf.d/local:z"
```

* Replace all references to standard UDP/TCP outside listening ports (typically 514) on the _left hand side only_ of the port pairs
with arbitrary high-numbered (> 1024) ports so that the container can listen without root privileges.  The right hand side of the pairs
(also typically 514) should remain unchanged:

```
ExecStart=/usr/bin/podman run -p 2514:514 -p 2514:514/udp -p 6514:6514 
```

If not done in the "Prepare SC4S user" above, create the three local mount directories as instructed in the main instructions,
replacing the head of the directory `/opt/sc4s` with the sc4s service user's home directory as shown below:

```
mkdir /home/sc4s/local
mkdir /home/sc4s/archive
mkdir /home/sc4s/tls
```

## Remaining Setup

The remainder of the setup can be followed directly from the main setup instructions.