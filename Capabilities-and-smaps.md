
On some Linux versions it may be impossible for non-root users to read smaps files.

The file may appear to allow read:

```text
$ ls -l /proc/$$/smaps
-r--r--r-- 1 oracle oinstall 0 Apr  1 14:26 /proc/28953/smaps
```

Even so, the Linux capabilities system may prevent you from reading the file.

This can be changed by setting the `CAP_SYS_PTRACE' capability for `cat`:

```text
# getcap /usr/bin/cat
# setcap cap_sys_ptrace+ep /usr/bin/cat
# getcap /usr/bin/cat
/usr/bin/cat = cap_sys_ptrace+ep

```

While it may not be a good idea to do this to `cat`, it is fine on this test system.

And now oracle can read its own smaps file:

```text
$ wc /proc/$$/smaps
756 2522 23287 /proc/28953/smaps
```

More information is available via `man capabilities`








