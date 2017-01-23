#!/bin/bash

# -----------------------------------------------------------------------------
opt_p="4"
opt_src=
opt_dst=
opt_s="10M"
opt_v=
opt_x=
opt_ropt="-a --delete -q"
opt_sed=$(which sed)
opt_sort=$(which sort)
opt_find=$(which find)
opt_rsync=$(which rsync)
opt_xargs=$(which xargs)
starttime=$SECONDS

# -----------------------------------------------------------------------------
function check_exe() 
{
    if ! [ -x "$2" ]; then
        usage "can not find '$1' executable ($2)"
    fi    
}

# -----------------------------------------------------------------------------
function usage() 
{
    if [ "$1" ]; then echo; echo "ERROR: $1!"; fi
    echo "
Usage: $(basename $0) [options]
Valid options, * - required:
    -src   DIR   *  source directory
    -dst   DIR   *  destination directory
    -s     SIZE     file size to put it in papallel process, default: '$opt_size' 
                    about size's format see 'man find', command line key '-size' 
    -p     N        max processes, >0, default: '$opt_p'
    -v              be verbose
    -x              print processes info and exit (use to 
    --     OPT      rsync options, default: '$opt_ropt'
"
    exit 1
}

# -----------------------------------------------------------------------------
while [ "$1" ]; do
    case "$1" in
        '-p')       opt_p="$2"; shift 2;;
        '-s')       opt_s="$2"; shift 2;;
        '-v')       opt_v=true; shift;;
        '-x')       opt_x=true; shift;;
        '-src')     opt_src="$2"; shift 2;;
        '-dst')     opt_dst="$2"; shift 2;;
        '--')       shift; opt_ropt="$@"; break;;
        *)          usage "invalid option '$1'";;
    esac
done

# -----------------------------------------------------------------------------
if [ -z "$opt_src" ]; then usage "no '-src' option"; fi
if [ -z "$opt_dst" ]; then usage "no '-dst' option"; fi
check_exe 'rsync' $opt_rsync;
check_exe 'xargs' $opt_xargs;
check_exe 'find' $opt_find;
check_exe 'sort' $opt_sort;
check_exe 'sed' $opt_sed;
if ! [[ "$opt_p" =~ ^[0-9]+$ ]]; then usage "invalid '-p' option ($opt_p)"; fi
if [ $opt_p -lt 1 ]; then usage "option '-p' can not be 0"; fi
if ! [[ "$opt_s" =~ ^[0-9]+[bcwkMG]$ ]]; then usage "invalid '-s' option ($opt_s)"; fi

# -----------------------------------------------------------------------------
declare -A  parts

# -----------------------------------------------------------------------------
function rm_tmp {
    for(( i = 0; i <= $opt_p; i++ )); do
        rm -f "${parts[$i,1]}" 
    done
    TZ=UTC0 printf '%(Done in %H:%M:%S)T\n' $(($SECONDS-$starttime))
}

# -----------------------------------------------------------------------------
function print_files {
    echo "$1 : $( cat "$1" | wc -l )"
}

# -----------------------------------------------------------------------------
parts[0,0]=0
parts[0,1]=$(tempfile -p 'prs-' -s '.all')
for(( i = 1; i <= $opt_p; i++ )); do
    parts[$i,0]=0
    parts[$i,1]=$(tempfile -p 'prs-' -s '.include')
done

# -----------------------------------------------------------------------------
#var='34361835520 /home/klopp/xxx/vbox/Mint64/Mint64.vd'
#var=${var// */}
#echo "$var"
#exit

declare -a files_list
OLD_IFS="$IFS"
IFS=$'\n'
files_list=($($opt_find "$opt_src/" -type f -size +$opt_s -printf "%s %p\n" | $opt_sort -gr))

max=$(($opt_p-1))
if [ $opt_p -lt 2 ]; then max=1; fi

j=-1
rx='^([0-9]+) (.*)$'
while [ $j -lt ${#files_list[*]} ]; do

    for(( i = 1; i <= $max; i++ )); do

        j=$(($j+1))                              
        if ! [[ "${files_list[$j]}" =~ $rx ]]; then break; fi 
        file_size=${BASH_REMATCH[1]}
        file_name=${BASH_REMATCH[2]}
        file_name=${file_name#$opt_src}
        if [[ $opt_p -lt 2 || "${parts[$i,0]}" < "${parts[$(($i+1)),0]}" ]]; then
           echo "$file_name" >> "${parts[$i,1]}"
    	   parts[$i,0]=$((${parts[$i,0]}+$file_size))
	   else
           echo "$file_name" >> "${parts[$(($i+1)),1]}"
           parts[$(($i+1)),0]=$((${parts[$(($i+1)),0]}+$file_size))
	   fi
    done
done

files_list=($($opt_find "$opt_src/" -type f -size $opt_s -or -size -$opt_s -printf "%s %p\n" | $opt_sort -gr))
IFS="$OLD_IFS"

j=-1
rx='^([0-9]+) (.*)$'
while [ $j -lt ${#files_list[*]} ]; do
    j=$(($j+1))                              
    if ! [[ "${files_list[$j]}" =~ $rx ]]; then break; fi    
    parts[0,0]=$((${parts[0,0]}+${BASH_REMATCH[1]}))
    file_name=${BASH_REMATCH[2]}
    file_name=${file_name#$opt_src}
    echo "$file_name" >> "${parts[0,1]}"
done

if [[ $opt_x || $opt_v ]]; then
    for(( i = 1; i <= $opt_p; i++ )); do    
        printf "process %d: %'.f bytes\n" $i ${parts[$i,0]}
    done
    printf "main process: %'.f bytes\n" ${parts[0,0]}
fi
if [ $opt_x ]; then 
#    rm_tmp
    exit 0; 
fi

# -----------------------------------------------------------------------------
for file_name in ${!file_sizes[@]}; do
	echo ${file_sizes[$file_name]} $file_name
done | $opt_sort -gr | $opt_sed -e 's/^[0-9 ]*//g' | \
	$opt_xargs -I {} -n 1 -P $(($opt_p+1)) \
	   $opt_rsync $opt_ropt --files-from="{}" "$opt_src/" "$opt_dst/" &
wait
rm_tmp
exit 0

# -----------------------------------------------------------------------------
# That's All, Folks!
# -----------------------------------------------------------------------------
