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
sleep 4
TZ=UTC0 printf '%(%H:%M:%S)T\n' $(($SECONDS-$starttime))
exit

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
declare -A  file_sizes
declare -a  part_files

# -----------------------------------------------------------------------------
function rm_tmp {
    for file_name in ${part_files[@]}; do
        rm -f "$file_name" 
    done
}

# -----------------------------------------------------------------------------
function print_files {
    echo "$1 : $( cat "$1" | wc -l )"
}

# -----------------------------------------------------------------------------
part_files[0]="$(tempfile -p 'prs-' -s '.all')"
file_sizes[${part_files[0]}]=0 
for(( i = 1; i <= $opt_p; i++ )); do
    part_files[$i]="$(tempfile -p 'prs-' -s '.include')"
    file_sizes[${part_files[$i]}]=0 
done

# -----------------------------------------------------------------------------
declare -a files_list
files_list=($($opt_find "$opt_src/" -type f -size +$opt_s -printf "%s %p\n" | $opt_sort -gr))

max=$(($opt_p-1))
if [ $opt_p -lt 2 ]; then max=1; fi

while [ ${#files_list[*]} -gt 0 ]; do

    for(( i = 1; i <= $max; i++ )); do

        file_name="${files_list[1]}"
        if [ -z "$file_name" ]; then break; fi
        file_name=${file_name#$opt_src}
        file_size="${files_list[0]}"
        files_list=("${files_list[@]:2}")

        file1=${part_files[$i]}
        file2=${part_files[$(($i+1))]}

        if [[ $opt_p -lt 2 || "${file_sizes[$file1]}" < "${file_sizes[$file2]}" ]]; then
    	   echo "$file_name" >> "$file1"
    	   file_sizes[$file1]=$((${file_sizes[$file1]}+$file_size))
	else
        echo "$file_name" >> "$file2"
    	   file_sizes[$file2]=$((${file_sizes[$file2]}+$file_size))
	fi
    done
done

files_list=($($opt_find "$opt_src/" -type f -size $opt_s -or -size -$opt_s -printf "%s %p\n" | $opt_sort -gr))

for(( i = 0; i < ${#files_list[*]}; i += 2 )); do
    file_name="${files_list[$(($i+1))]}"
    if [ -z "$file_name" ]; then break; fi
    file_name=${file_name#$opt_src}
    file_size="${files_list[$i]}"

    file_sizes[${part_files[0]}]=$((${file_sizes[${part_files[0]}]}+$file_size))
    echo "$file_name" >> "${part_files[0]}"

done

if [[ $opt_x || $opt_v ]]; then
    i=1    
    for file_name in ${!file_sizes[@]}; do
        printf "process %d: %'.f bytes\n" $i ${file_sizes[$file_name]}
        i=$(($i+1));
    done
fi
if [ $opt_x ]; then exit 0; fi

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
