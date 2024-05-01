#!/bin/bash
trap "exit" INT


FILENAME=test.lst
DONEFILE="done.txt"
TEST=false
NCORES=$[$(nproc)-1]
JUMP=false
MAXINT=100000000000000 # this is just a verly large integer
NCOMMANDS=$MAXINT
NSKIP=0

# read in options
while [ -n "$1" ]
do
  case "$1" in
  -f) FILENAME="$2"
      shift
      ;;
  -d) DONEFILE="$2"
      shift
      ;;
  -N) NCOMMANDS="$2"
      shift
      ;;
  -S) NSKIP="$2"
      shift
      ;;
  -t) TEST=true
      ;;
  -c) NCORES="$2"
      shift
	if [[ "$NCORES" == "0" ]]
	then
	  echo "Use only 1 core"
	  NCORES=1
	else
	  if (( $NCORES < $(nproc) ))
	  then
	    echo "Use $NCORES core(s)"
	  else
	    echo "Given number of cores $NCORES larger than available cores!"
	    NCORES=$[$(nproc)-1]
	    echo "Use $NCORES cores instead..."
	  fi
	fi
      ;;
  -y) JUMP=true
      ;;
  -h) echo "--------------------------------------------------------------------"
      echo "Help for cluster_run.sh"
      echo "--------------------------------------------------------------------"
      echo "-f FILENAME  : set file with commands to run in parallel ($FILENAME)"
      echo "-d DONEFILE  : file saving run times when done ($DONEFILE)"
      echo "-N NCOMMANDS : maximal number of commands to run from FILENAME ($(if [[ $NCOMMANDS == $MAXINT ]]; then echo all; else echo $NCOMMANDS; fi))"
      echo "-S NSKIP     : number of commands to skip from FILENAME ($NSKIP)"
      echo "-t           : start in test-mode, only echo, no run ($(if [[ $TEST == true ]]; then echo yes; else echo no; fi))"
      echo "-c NCORES    : define number of parallely used cores <= nproc-1 ($NCORES)"
      echo "-y           : don't wait for user to check the input"
      echo "-h           : display this help"
      echo "--------------------------------------------------------------------"
      exit
      ;;
  *)  echo "Option $1 not recognized! Ignored.." ;;
  esac

  shift
done

# remove done file
if [[ -f "$DONEFILE" ]]
then
  echo "Remove old file '$DONEFILE'"
  rm $DONEFILE
fi



# print read options
echo ""
echo "Provided options:"
if [[ -f "$FILENAME" ]]
then
  echo "- filename is \"$FILENAME\""
else
  echo "ERROR: No file \"$FILENAME\" found! Abort..."
  exit
fi

if [[ "$NCOMMANDS" != "$MAXINT" ]]
then
  echo "- Only run over $NCOMMANDS commands."
else
  echo "- Run over all commands."
fi

if [[ "$NSKIP" != "0" ]]
then 
  echo "- Skip $NSKIP commands."
else
  echo "- No commands are skipped."
fi

echo "- Run $NCORES commands in parallel."


number_commands_total=$(cat $FILENAME | wc -l)
number_commands=$[$number_commands_total-$NSKIP]

if [[ "$number_commands" -ge "$NCOMMANDS" ]]
then 
  number_commands=$NCOMMANDS
fi

echo "- Really have to run over $number_commands."
echo ""

if [[ $TEST == true ]]
then
  echo "-----------------------------------------------"
  echo "THIS IS JUST A TEST. Commands will not be started."
  echo "No files will be deleted or created."
  echo "No folders will be created or old files deleted."
  echo "-----------------------------------------------"
fi

# wait for user to confirm settings
if [[ $JUMP == true ]]
then
  echo "Jump over check. Start with commands..."
elif 
  echo "Please check if everything is okay. ('Enter' to continue): "
  read -t 10 -p ""
then
  echo "Start with commands..."
else
  echo "Timeout!"
  echo "exiting..."
  exit
fi

echo "Started at $(date)."
starttime=`date +%s`
starttimenice=$(date)

# Assign execution of this script to core 0:
taskset -cp 0 $$

current_proc=0
total_procs=0
max_procs=0
finished_procs=0
commands_done=0
commands_skipped=0

# run commands
while IFS="" read -r p || [ -n "$p" ]
do
  if [[ "$commands_skipped" -lt "$NSKIP" ]]
  then 
    commands_skipped=$[$commands_skipped+1]
    continue
  fi
  
  if [[ "$commands_done" -ge "$number_commands" ]]
  then 
    echo "no more commands to run"
    break
  else 
    commands_done=$[$commands_done+1]
  fi

  if [[ "$NCORES" > "1" ]] # don't do this with only one core
  then
    # if all cores are busy, wait for one to finish
    while (( $(jobs -l | grep "Running" | wc -l) == $NCORES ))
    do # check every second if a job finished
      sleep 0.1
    done 

    if (( $max_procs >= $NCORES )) # all cores were busy at least once
    then # search job that is done 
      current_proc=1
      finished_procs=$[$finished_procs+1]
      echo "Finished process $finished_procs/$number_commands. Start next process..."
      for running_proc in ${running_procs[*]}
      do
        if (( $(jobs -l | grep "Running" | grep $running_proc | wc -l) == 0 ))
        then # found finished job
          break
        else # try next process id
          current_proc=$[$current_proc+1]
        fi
      done
    else # not all cores were busy yet
      current_proc=$[$current_proc+1]
      max_procs=$[$max_procs+1]
    fi
  fi 

  total_procs=$[$total_procs+1]
  

  echo "Start process $total_procs/$number_commands"
  echo $(echo $p)

  if [[ "$NCORES" > "1" ]]
  then  
    if [[ $TEST == true ]]
    then
      sleep 0.001 &
    else
      eval $(echo $p) &
    fi
    running_procs[$current_proc]=$!
    taskset -cp $current_proc $!
  
  else 
    if [[ $TEST == false ]]
    then
      eval $(echo $p) 
    fi
  fi
done < $FILENAME;

if [[ "$NCORES" > "1" ]]
then
  # wait for last processes to finish
  echo "No more processes to start. Wait for the remaining ones to finish..."
  for running_proc in ${running_procs[*]}
  do
    wait $running_proc
    finished_procs=$[$finished_procs+1]
    echo "Finished process $finished_procs/$number_commands."
  done
fi
echo "Finished running over all files."
echo "--------------------------------"
echo
echo "Done with everything. Create file $DONEFILE"

stoptime=`date +%s`
stoptimenice=$(date)

runtime=$(($stoptime-$starttime))
hours=$(($runtime/3600))
restruntime=$(($runtime%3600))
minutes=$(($restruntime/60))
seconds=$(($restruntime%60))
echo "Code endet at $(date)."
echo "Full runtime = ${hours}h${minutes}min${seconds}s"

if [[ $TEST == true ]]
then
  echo 'echo "Code started at: $starttimenice
  Code ended at: $stoptimenice
  Coded needed in total: ${hours}h${minutes}min${seconds}s" > $DONEFILE'
else
  echo "Code started at: $starttimenice
  Code ended at: $stoptimenice
  Coded needed in total: ${hours}h${minutes}min${seconds}s" > $DONEFILE
fi

