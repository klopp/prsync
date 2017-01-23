#!/bin/bash

# -----------------------------------------------------------------------------
opt_p="4"
opt_b="4"
opt_s="10M"
opt_src=
opt_dst=
opt_v=
opt_x=
opt_k=
opt_d=
opt_rm=
opt_ropt="-a --delete -q"
opt_sort=$(which sort)
opt_find=$(which find)
opt_rsync=$(which rsync)
opt_xargs=$(which xargs)
starttime=$SECONDS
OLD_IFS="$IFS"
IFS=$'\n'

# -----------------------------------------------------------------------------
function pv {
    if [ $opt_v ]; then
        printf "$@"
        echo 
    fi
}

# -----------------------------------------------------------------------------
function check_exe() 
{
    if ! [ -x "$2" ]; then
        usage "can not find '$1' executable ($2)"
    fi    
}

# -----------------------------------------------------------------------------
declare -A  parts

# -----------------------------------------------------------------------------
function cleanup {

    local rc="$1"
    if [ -z "$rc" ]; then rc=0; fi 
    pv "Waiting for processes..."
    wait
    if ! [ $opt_k ] ; then
        pv "Removing temporaty files..."
        for(( i = 0; i <= $opt_p; i++ )); do
            rm -f "${parts[$i,1]}" 
        done
    fi
    TZ=UTC0 printf "%(Done in %H:%M:%S)T\n" $(($SECONDS-$starttime))
    IFS="$OLD_IFS"
    exit $rc
}

# -----------------------------------------------------------------------------
function usage() 
{
    if [ "$1" ]; then echo; echo "ERROR: $1!"; fi
    echo "
Usage: $(basename $0) [options]
Valid options, * - required:
    -src   DIR   *  source directory
    -dst   DIR   *  destination directory (see '-x' option)
    -s     SIZE     file size to put it in papallel process, default: '$opt_size' 
                    about size's format see 'man find', command line key '-size' 
    -p     N        max processes, >0, default: '$opt_p'
    -v              be verbose
    -r              delete '-dst' directory before sync
    -x              print processes info and exit (no '-dst' required)
    -d              show debug info (some as '-x', but launch sync) 
    -k              keep temporary files 
    -b     N        show N biggest files with -x, default: '$opt_b'  
    --     OPT      rsync options, default: '$opt_ropt'
"
    opt_v=false
    opt_d=false
    opt_x=false
    cleanup 1
}

# -----------------------------------------------------------------------------
while [ "$1" ]; do
    case "$1" in
        '-p')       opt_p="$2"; shift 2;;
        '-b')       opt_b="$2"; shift 2;;
        '-s')       opt_s="$2"; shift 2;;
        '-v')       opt_v=true; shift;;
        '-x')       opt_x=true; shift;;
        '-d')       opt_d=true; shift;;
        '-d')       opt_d=true; shift;;
        '-r')       opt_rm=$(which rm); shift;;
        '-k')       opt_k=true; shift;;
        '-src')     opt_src="$2"; shift 2;;
        '-dst')     opt_dst="$2"; shift 2;;
        '--')       shift; opt_ropt="$@"; break;;
        *)          usage "invalid option '$1'";;
    esac
done

# -----------------------------------------------------------------------------
check_exe 'find' $opt_find;
check_exe 'sort' $opt_sort;
check_exe 'rsync' $opt_rsync;
if [ $opt_rm ]; then check_exe 'rm' $opt_rm; fi
if [ -z "$opt_src" ]; then usage "no '-src' option"; fi
if [[ -z "$opt_dst" && -z $opt_x ]]; then usage "no '-dst' option"; fi
if ! [[ "$opt_p" =~ ^[0-9]+$ ]]; then usage "invalid '-p' option ($opt_p)"; fi
if [ $opt_p -lt 1 ]; then usage "option '-p' can not be 0"; fi
if ! [[ "$opt_b" =~ ^[0-9]+$ ]]; then usage "invalid '-b' option ($opt_b)"; fi
if [ $opt_b -lt 1 ]; then usage "option '-b' can not be 0"; fi
if ! [[ "$opt_s" =~ ^[0-9]+[bcwkMG]$ ]]; then usage "invalid '-s' option ($opt_s)"; fi

# -----------------------------------------------------------------------------
parts[0,0]=0
parts[0,1]=$(tempfile -p 'prs-' -s '.include')
parts[0,2]=0
for(( i = 1; i <= $opt_p; i++ )); do
    parts[$i,0]=0
    parts[$i,1]=$(tempfile -p 'prs-' -s '.include')
    parts[$i,2]=0
done

# -----------------------------------------------------------------------------
declare -A  biggest
declare -a files_list

pv "Collecting files with size +%s..." $opt_s
files_list=($($opt_find "$opt_src/" -type f -size +$opt_s -printf "%s %p\n" | $opt_sort -gr))
max=$(($opt_p-1))
if [ $opt_p -lt 2 ]; then max=1; fi

rx="^([0-9]+) (.*)$"
j=-1
b=0 

while [ $j -lt ${#files_list[*]} ]; do

    for(( i = 1; i <= $max; i++ )); do

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

        if [[ $opt_p -lt 2 || "${parts[$i,0]}" -le "${parts[$(($i+1)),0]}" ]]; then
           echo "$file_name" >> "${parts[$i,1]}"
           if [ $opt_d ]; then echo "; $file_size ${parts[$i,0]}" >> "${parts[$i,1]}"; fi
    	   parts[$i,0]=$((${parts[$i,0]}+$file_size))
           parts[$i,2]=$((${parts[$i,2]}+1))
	   else
           echo "$file_name" >> "${parts[$(($i+1)),1]}"
           if [ $opt_d ]; then echo "; $file_size ${parts[$(($i+1)),0]}" >> "${parts[$(($i+1)),1]}"; fi
           parts[$(($i+1)),0]=$((${parts[$(($i+1)),0]}+$file_size))
           parts[$(($i+1)),2]=$((${parts[$(($i+1)),2]}+1))
	   fi
    done
done

# -----------------------------------------------------------------------------
pv "Collecting other files..."
files_list=($($opt_find "$opt_src/" -type f -size $opt_s -or -size -$opt_s -printf "%s %p\n" | $opt_sort -gr))
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
        if [ ${biggest[$i,0]} -gt 0 ]; then
            printf " %'18.f bytes '%s'\n" ${biggest[$i,0]} ${biggest[$i,1]}
        fi
    done 
fi

# -----------------------------------------------------------------------------
declare -a sorted
for(( i = 0; i <= $opt_p; i++ )); do
    sorted[${parts[$i,0]}]=${parts[$i,1]}
done

declare -a rsync_exec
for i in ${!sorted[@]}; do
    rsync_exec=("${sorted[$i]}" ${rsync_exec[@]})
done

declare -a rsync_args
IFS=' ' read -r -a rsync_args <<< "$opt_ropt"
if [ $opt_x ]; then 
    echo "Rsync arguments: "${rsync_args[@]}
    cleanup; 
fi 

# -----------------------------------------------------------------------------
if [ $opt_rm ]; then
    pv "Deleting directory '%s'..." $opt_dst
    $opt_rm -fr "$opt_dst"
    if [ -d "$opt_dst" ]; then 
        echo "ERROR: can not delete '$opt_dst'"
        cleanup 1 
    fi
fi
pv "Launching '%s' processes..." $opt_rsync
IFS=$'\n'
for file_name in ${rsync_exec[@]}; do
   echo "$file_name"
done | $opt_xargs -I {} -n 1 -P $(($opt_p+1)) \
        $opt_rsync --files-from="{}" ${rsync_args[@]} "$opt_src/" "$opt_dst/"

cleanup

# -----------------------------------------------------------------------------
# That's All, Folks!
# -----------------------------------------------------------------------------
