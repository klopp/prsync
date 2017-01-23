# Multi-threaded rsync wrapper

```
Usage: prsync.sh [options]
Valid options, * - required:
Valid options, * - required:
    -src   DIR   *  source directory
    -dst   DIR   *  destination directory (see '-x' option)
    -s     SIZE     file size to put it in papallel process, default: '10M' 
                    about size's format see 'man find', command line key '-size' 
    -p     N        max processes, >0, default: '4'
    -v              be verbose
    -x              print processes info and exit (no '-dst' required)
    -d              show debug info (some as '-x', but launch sync) 
    -k              keep temporary files 
    -b     N        show N biggest files with -x, default: '4'  
    --     OPT      rsync options, default: '-a -q --delete'
```