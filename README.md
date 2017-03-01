# Multi-threaded rsync wrapper

```
Multi-threaded rsync wrapper. (C) Vsevolod Lutovinov <klopp@yandex.ru>, 2017
Usage: prsync.sh [options]
Valid options:
    -d   DIR    destination directory (see '-x' option)
    -s   SIZE   file size to put it in additional papallel process, default: '10M'
                all files with lesser than SIZE size will be placed to 'root' process  
                (about size's format see 'man find', command line key '-size')
                if SIZE is '0' all files will be processed without 'root' process
    -p   N      additional processes, >0, default: '2'
    -v          be verbose
    -c          cleanup '-d' directory before sync
    -x          print processes info and exit (no '-d' required)
    -g          show debug info (some as '-x', but launch sync) 
    -k          keep temporary files 
    -b   N      show N biggest files with -x  
    --   "OPT"  set rsync options, default: '-a --delete -q'
    ++   "OPT"  add rsync options to current set
```