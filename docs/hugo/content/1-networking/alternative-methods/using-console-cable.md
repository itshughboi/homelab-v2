---
title: "Console Cable"
---

# Console Cable

For direct serial access to a router or switch when SSH isn't available.

---

## Connect and Open

1. Plug console cable from Macbook into the console port on the router/switch
2. Find the device:
```sh
cd /dev
ls | grep usb
```
3. Open the console:
```sh
screen /dev/tty.usbserial-A9BV5GD4
```
Replace `A9BV5GD4` with the actual device ID from the previous step.

4. Enter config mode:
```sh
configure
```

---

## Device Already In Use

If `screen` says the device is already in use:

1. Find the PID holding it:
```sh
lsof /dev/tty.usbserial-A9BV5GD4
```

2. Kill it:
```sh
kill <PID>
```

3. Try `screen` again.
