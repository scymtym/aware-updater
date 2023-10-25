Introduction
============

Build
=====

1. Install [SBCL](http://sbcl.org)

   On Debian-based distributions like Ubuntu,

   ```bash
   apt install sbcl make
   ```

   might suffice.

2. Install [Quicklisp](https://beta.quicklisp.org)

   ```bash
   wget https://beta.quicklisp.org/quicklisp.lisp
   sbcl --load quicklisp.lisp --eval '(quicklisp-quickstart:install :path "SOMEWHERE/quicklisp/")' --quit
   ```

3. Build

   ```bash
   LISP=sbcl QUICKLISP_DIRECTORY=SOMEWHERE/quicklisp make
   ```

Install
=======

Add the following entries to `/etc/sudoers` or to a new file in `/etc/sudoers.d`:

```
iata ALL = NOPASSWD: /usr/bin/nmcli
iata ALL = NOPASSWD: /usr/bin/systemctl
```

Add a systemd unit

```bash
sudo cp aware-updater.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable aware-updater
sudo systemctl start aware-updater
```

Usage
=====

Run the service as

```bash
$ ./updater
Listening on 0.0.0.0:4040
```
