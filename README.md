# Multi-threaded rsync wrapper

```
Usage: prsync.pl [options]
Valid options, * - required:
    -src   DIR   * source directory
    -dst   DIR   * destination directory
    -tmp   DIR     temporary directory, default: '/tmp'
    -rsync PATH    rsync executable, default: '/usr/bin/rsync'
    -sudo  [PATH]  use sudo [executable], defaults: NO, executable: '/usr/bin/sudo'
    -p     N       max processes, >1, default: '8'
    -v             increase verbosity
    -s             optimize for small files (try decrease -p for best results)
    -d             print debug information
    --     OPT     rsync options, default: '-a --delete --info=none,copy1,name1'
```