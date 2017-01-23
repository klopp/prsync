# Multi-threaded rsync wrapper

```
Multi-threaded rsync wrapper. (C) Vsevolod Lutovinov <klopp@yandex.ru>, 2017
Usage: prsync.sh [options]
Valid options, * - required:
    -src   DIR   *  source directory
    -dst   DIR   *  destination directory (see '-x' option)
    -s     SIZE     file size to put it in papallel process, default: '10M' 
                    about size's format see 'man find', command line key '-size' 
    -p     N        additional processes, >0, default: '2'
    -v              be verbose
    -c              cleanup '-dst' directory before sync
    -x              print processes info and exit (no '-dst' required)
    -d              show debug info (some as '-x', but launch sync) 
    -k              keep temporary files 
    -b     N        show N biggest files with -x, default: '4'  
    --     OPT      rsync options, default: '-a --delete -q'
```