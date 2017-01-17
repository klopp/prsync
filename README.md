# Multi-threaded rsync wrapper

```
Usage: prsync.pl [options]
Valid options, * - required:
    -src   DIR   * source directory
    -dst   DIR   * destination directory
    -tmp   DIR     temporary directory, default: '/tmp'
    -rsync PATH    rsync executable, default: '/usr/bin/rsync'
    -sudo  [PATH]  use sudo [executable], default: NO, executable: '/usr/bin/sudo'
    -p     N       max processes, > 1, default: '16'
    -v             increase verbosity
    -d             print debug information
    --     OPT     rsync options, default: '-a --delete --info=none,name1,copy1'
```