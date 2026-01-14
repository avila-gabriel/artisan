`test.sh` will reproduce the same vm we aim for production.
copy and paste `provision.sh` and execute it in the fresh production vm and boom!



# ADMIN usage:

**Update without touching production**

```bash
ssh into the vm
make update
```

* builds new version
* starts it on the other port
* production keeps running

---

**Watch logs**

```bash
make logs-prod     # current live server
make logs-preview  # new version
```

`make update` until its healthy.

---

**Switch when ready**

```bash
make switch
```

* nginx points to new version
* old server stops
* small blip is acceptable

---

That’s it.

