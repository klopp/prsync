#!/bin/bash

# -----------------------------------------------------------------------------
opt_p="2"
opt_b="4"
opt_s="10M"
opt_src=
opt_dst=
opt_v=
opt_x=
opt_k=
opt_d=
opt_ropt="-a --delete -q"
opt_sort=$(which sort)
opt_find=$(which find)
opt_tmpf=$(which tempfile)
opt_rsync=$(which rsync)
opt_xargs=$(which xargs)
starttime=$SECONDS
OLD_IFS="$IFS"
IFS=$'\n'

# -----------------------------------------------------------------------------
function pv {
    if [ $opt_v ]; then printf "$@"; echo; fi
}

# -----------------------------------------------------------------------------
function check_exe() {
    if ! [ -x "$2" ]; then usage "can not find '$1' executable ($2)"; fi    
}

# -----------------------------------------------------------------------------
declare -A  parts

# -----------------------------------------------------------------------------
function cleanup {

    local rc="$1"
    if [ -z "$rc" ]; then rc=0; fi
    if [ $rc ]; then opt_v=; opt_d=; opt_x=; fi 
    pv "Waiting for processes..."
    wait
    if ! [ $opt_k ] ; then
        pv "Removing temporaty files..."
        for(( i = 0; i <= $opt_p; i++ )); do
            rm -f "${parts[$i,1]}" 
        done
    fi
    TZ=UTC0 
    pv "%(Done in %H:%M:%S)T\n" $(($SECONDS-$starttime))
    IFS="$OLD_IFS"
    exit $rc
}

# -----------------------------------------------------------------------------
function usage() 
{
    if [ "$1" ]; then echo; echo "ERROR: $1!"; fi
    echo "
Multi-threaded rsync. (C) Vsevolod Lutovinov <klopp@yandex.ru>, 2017
Usage: $(basename $0) [options]
Valid options, * - required:
    -src   DIR   *  source directory
    -dst   DIR   *  destination directory (see '-x' option)
    -s     SIZE     file size to put it in papallel process, default: '$opt_s' 
                    about size's format see 'man find', command line key '-size' 
    -p     N        additional processes, >0, default: '$opt_p'
    -v              be verbose
    -c              cleanup destination directory
    -x              print processes info and exit (no '-dst' required)
    -d              show debug info (some as '-x', but launch sync) 
    -k              keep temporary files 
    -b     N        show N biggest files with -x, default: '$opt_b'  
    --     OPT      rsync options, default: '$opt_ropt'
"
    cleanup 1
}

# -----------------------------------------------------------------------------
if [ -z "$1" ]; then usage; fi
while [ "$1" ]; do
    case "$1" in
        '-src')     opt_src="$2"; shift 2;;
        '-dst')     opt_dst="$2"; shift 2;;
        '-s')       opt_s="$2"; shift 2;;
        '-p')       opt_p="$2"; shift 2;;
        '-v')       opt_v=true; shift;;
        '-c')       opt_c=true; shift;;
        '-x')       opt_x=true; shift;;
        '-d')       opt_d=true; shift;;
        '-k')       opt_k=true; shift;;
        '-b')       opt_b="$2"; shift 2;;
        '--')       shift; opt_ropt="$@"; break;;
        *)          usage "invalid option '$1'";;
    esac
done

# -----------------------------------------------------------------------------
check_exe 'find' $opt_find;
check_exe 'sort' $opt_sort;
check_exe 'rsync' $opt_rsync;
check_exe 'tempfile' $opt_tmpf;
if [ -z "$opt_src" ]; then usage "no '-src' option"; fi
if [[ -z "$opt_dst" && -z $opt_x ]]; then usage "no '-dst' option"; fi
if [ $opt_rm ]; then check_exe 'rm' $opt_rm; fi
if ! [[ "$opt_p" =~ ^[0-9]+$ ]]; then usage "invalid '-p' option ($opt_p)"; fi
if [ $opt_p -lt 1 ]; then usage "option '-p' can not be 0"; fi
if ! [[ "$opt_b" =~ ^[0-9]+$ ]]; then usage "invalid '-b' option ($opt_b)"; fi
if [ $opt_b -lt 1 ]; then usage "option '-b' can not be 0"; fi
if ! [[ "$opt_s" =~ ^[0-9]+[bcwkMG]$ ]]; then usage "invalid '-s' option ($opt_s)"; fi
# -- remove trailing slashes:
opt_dst=${opt_dst%"${opt_dst##*[!/]}"}
opt_src=${opt_src%"${opt_src##*[!/]}"}


parts[0,0]=0
parts[0,1]=$($opt_tmpf -p 'prs-' -s '.include')
parts[0,2]=0
for(( i = 1; i <= $opt_p; i++ )); do
    parts[$i,0]=0
    parts[$i,1]=$($opt_tmpf -p 'prs-' -s '.include')
    parts[$i,2]=0
done

# -----------------------------------------------------------------------------
declare -A biggest
declare -a files_list

pv "Collecting files with size +%s..." $opt_s
if ! [ -d "$opt_src/" ]; then echo "ERROR: can not read from '$opt_src'!"; cleanup 1; fi
files_list=($($opt_find "$opt_src/" -mindepth 1 -type f -size +$opt_s -printf "%s %p\n" | $opt_sort -gr))

rx="^([0-9]+) (.*)$"
j=-1
b=0 
nan=0
for ((i = 1, n = 2;; n = 1 << ++i)); do
  if [[ ${n:0:1} == '-' ]]; then nan=$(((1 << i) - 1)); break; fi
done

while [ $j -lt ${#files_list[*]} ]; do

    j=$(($j+1))
    if ! [[ "${files_list[$j]}" =~ $rx ]]; then break; fi 
    file_size=${BASH_REMATCH[1]}
    file_name=${BASH_REMATCH[2]}
    file_name=${file_name#$opt_src}

    if [ $b -lt $opt_b ]; then
        biggest[$b,0]=$file_size
        biggest[$b,1]=$file_name
        b=$((b+1))
    fi    
    
    min=$nan
    k=0
    for(( i = 1; i <= $opt_p; i++ )); do
        if [ ${parts[$i,0]} -le $min ]; then 
            min=${parts[$i,0]}
            k=$i
        fi
    done        

    echo "$file_name" >> "${parts[$k,1]}"
    if [ $opt_d ]; then echo "; $file_size ${parts[$k,0]}" >> "${parts[$k,1]}"; fi
    parts[$k,0]=$((${parts[$k,0]}+$file_size))
    parts[$k,2]=$((${parts[$k,2]}+1))
done

# -----------------------------------------------------------------------------
pv "Collecting other files..."
files_list=($($opt_find "$opt_src/" -mindepth 1 -type f -not -size +$opt_s -printf "%s %p\n" | $opt_sort -gr))
j=-1
while [ $j -lt ${#files_list[*]} ]; do
    j=$(($j+1))                              
    if ! [[ "${files_list[$j]}" =~ $rx ]]; then break; fi    
    parts[0,0]=$((${parts[0,0]}+${BASH_REMATCH[1]}))
    parts[0,2]=$((${parts[0,2]}+1))
    file_name=${BASH_REMATCH[2]}
    file_name=${file_name#$opt_src}
    echo "$file_name" >> "${parts[0,1]}"
    if [ $opt_d ]; then echo "; ${BASH_REMATCH[1]} ${parts[0,0]}" >> "${parts[0,1]}"; fi
done

if [[ $opt_x || $opt_d ]]; then
    echo "Additional processes:"
    for(( i = 1; i <= $opt_p; i++ )); do    
        printf " files: %8d, bytes: %'18.f (%s)\n" ${parts[$i,2]} ${parts[$i,0]} ${parts[$i,1]}
    done
    printf "Main process:\n files: %8d, bytes: %'18.f (%s)\n" ${parts[0,2]} ${parts[0,0]} ${parts[0,1]}
    echo "Biggest files:"
    for(( i = 0; i < $opt_b; i++ )); do
        if ! [ -z ${biggest[$i,1]} ]; then
            printf " %'18.f bytes '%s'\n" ${biggest[$i,0]} ${biggest[$i,1]}
        fi
    done 
fi

# -----------------------------------------------------------------------------
declare -a sorted
total_files=0
for(( i = 0; i <= $opt_p; i++ )); do
    if [ ${parts[$i,2]} -gt 0 ]; then
        total_files=$(($total_files+${parts[$i,2]}))
        sorted[${parts[$i,0]}]=${parts[$i,1]}
    fi
done

declare -a rsync_exec
for i in ${!sorted[@]}; do
    rsync_exec=("${sorted[$i]}" ${rsync_exec[@]})
done

declare -a rsync_args
IFS=' ' read -r -a rsync_args <<< "$opt_ropt"
if [ $opt_x ]; then echo "Rsync arguments: "${rsync_args[@]}; fi

# -----------------------------------------------------------------------------
if [ $total_files -eq 0 ]; then
    pv "Notice: no files found in '$opt_src'!";
fi

if [ $opt_x ]; then cleanup; fi

if [ $opt_c ]; then
    pv "Cleaning up '$opt_dst'..."
    $opt_find "$opt_dst" -mindepth 1 -exec $opt_rm -fr {} +
fi

pv "Launching '%s' processes..." $opt_rsync
IFS=$'\n'
for file_name in ${rsync_exec[@]}; do
   echo "$file_name"
done | $opt_xargs -I {} -n 1 -P $(($opt_p+1)) \
        $opt_rsync --files-from="{}" ${rsync_args[@]} "$opt_src/" "$opt_dst/"
wait
pv "Last pass: sync root..."
$opt_rsync ${rsync_args[@]} "$opt_src/" "$opt_dst/"

cleanup

# -----------------------------------------------------------------------------
# That's All, Folks!
# -----------------------------------------------------------------------------
