#!/usr/bin/bash
# spincheck.sh, logs fan and temperature data
VERSION="2020-06-17x"

# Run as superuser. See notes at end.

# fohlsso2 2023-08-06
# modified to work with linux
# and maybe with ssd:s too
# the first line still needs to be manually edited for linux/bsd path
# linux is /usr/bin/bash and bsd is /usr/local/bin/bash
# modified to work with a third fan zone and eight fans
# because my test board Supermicro X10SRG-F splits the peripheral fans into two zones

# To keep the need for user edits lower we try to have both linux and bsd stuff in here
SYSTEM=$(uname)
if [[ "$SYSTEM" == "Linux" ]] ; then
    EXEPATH="/usr"
else
    EXEPATH="/usr/local"
fi
echo "Got system as '"$SYSTEM"', setting exec path as '"$EXEPATH"'."

# Path to ipmitool.  If you're doing VM 
# you may need to add (after first quote) the following to 
# remotely execute commands.
#  -H <hostname/ip> -U <username> -P <password> 
# We'll let the script try to find the path for you, but if that doesnt work, edit the two lines below
# IPMITOOL=/usr/bin/ipmitool
IPMITOOL=$(which ipmitool)
echo -e "Got IPMITOOL installed at '"$IPMITOOL"' \n"

# Creates logfile and sends all stdout and stderr to the log, 
# leaving the previous contents in place. If you want to append to existing log, 
# add '-a' to the tee command.

# If you want the log in the same place as the script keep this
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
LOG=$DIR/"spincheck.log"

# or if you want the log somewhere else, disable the two lines above and uncomment the one below
#LOG=/mnt/MyPool/MyDataSet/MyDirectory/spincheck.log  # Change to your desired log location/name

exec > >(tee -i $LOG) 2>&1

SP=33.57	#  Setpoint mean drive temp (C), for information only

##############################################
# function get_disk_name
# Get disk name from current LINE of DEVLIST
##############################################
# The awk statement works by taking $LINE as input,
# setting '(' as a _F_ield separator and taking the second field it separates
# (ie after the separator), passing that to another awk that uses
# ',' as a separator, and taking the first field (ie before the separator).
# In other words, everything between '(' and ',' is kept.

# camcontrol output for disks on HBA seems to change  every version,
# so need 2 options to get ada/da disk name.
# the linux output is already filtered using the lsblk command
function get_disk_name {
    if [ "$SYSTEM" == "Linux" ] ; then
        DEVID=$(echo "$LINE")
    else
		if [[ $LINE == *"(p"* ]] ; then     # for (pass#,[a]da#)
			DEVID=$(echo $LINE | awk -F ',' '{print $2}' | awk -F ')' '{print$1}')
		else                                # for ([a]da#,pass#)
			DEVID=$(echo $LINE | awk -F '(' '{print $2}' | awk -F ',' '{print$1}')
		fi
    fi
}

############################################################
# function print_header
# Called when script starts and each quarter day
############################################################
function print_header {
   DATE=$(date +"%A, %b %d")
   printf "\n%s \n" "$DATE"
   echo -n "          "
   while read LINE ; do
      get_disk_name
      printf "%-5s" $DEVID
   done <<< "$DEVLIST"             # while statement works on DEVLIST

   # standard list of columns
#   printf "%4s %5s %5s %3s %5s %5s %5s %5s %5s %5s %5s %-7s" "Tmax" "Tmean" "ERRc" "CPU" "FAN1" "FAN2" "FAN3" "FAN4" "FANA" "Fan%0" "Fan%1" "MODE" 

   # extended list of columns for my weird mobo with eight fans and three zones
   printf "%4s %5s %5s %3s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s %-7s" "Tmax" "Tmean" "ERRc" "CPU" "FAN1" "FAN2" "FAN3" "FAN4" "FANA" "FANB" "FANC" "FAND" "Fan%0" "Fan%1" "Fan%2" "MODE" 

}

#################################################
# function manage_data: Read, process, print data
#################################################
function manage_data {
   Tmean=$(echo "scale=3; $Tsum / $i" | bc)
   ERRc=$(echo "scale=2; $Tmean - $SP" | bc)
   # Read duty cycle, convert to decimal.
   # May need to disable these 3 lines as some boards apparently return
   # incorrect data. In that case just assume $DUTY hasn't changed.
   DUTY0=$($IPMITOOL raw 0x30 0x70 0x66 0 0) # in hex
   DUTY0=$((0x$(echo $DUTY0)))   # strip leading space and decimate
   DUTY1=$($IPMITOOL raw 0x30 0x70 0x66 0 1) # in hex
   DUTY1=$((0x$(echo $DUTY1)))   # strip leading space and decimate
   DUTY2=$($IPMITOOL raw 0x30 0x70 0x66 0 2) # in hex
   DUTY2=$((0x$(echo $DUTY2)))   # strip leading space and decimate
   # Read fan mode, convert to decimal.
   MODE=$($IPMITOOL raw 0x30 0x45 0) # in hex
   MODE=$((0x$(echo $MODE)))   # strip leading space and decimate
   # Text for mode
   case $MODE in
      0) MODEt="Standard" ;;
      4) MODEt="HeavyIO" ;;
      2) MODEt="Optimal" ;;
      1) MODEt="Full" ;;
   esac
   # Get reported fan speed in RPM.
   # Get reported fan speed in RPM from sensor data repository.
   # Takes the pertinent FAN line, then a number with 3 to 5 
   # consecutive digits
   SDR=$($IPMITOOL sdr)
   RPM_FAN1=$(echo "$SDR" | grep "FAN1" | grep -Eo '[0-9]{3,5}')
   RPM_FAN2=$(echo "$SDR" | grep "FAN2" | grep -Eo '[0-9]{3,5}')
   RPM_FAN3=$(echo "$SDR" | grep "FAN3" | grep -Eo '[0-9]{3,5}')
   RPM_FAN4=$(echo "$SDR" | grep "FAN4" | grep -Eo '[0-9]{3,5}')
   RPM_FANA=$(echo "$SDR" | grep "FANA" | grep -Eo '[0-9]{3,5}')
   RPM_FANB=$(echo "$SDR" | grep "FANB" | grep -Eo '[0-9]{3,5}')
   RPM_FANC=$(echo "$SDR" | grep "FANC" | grep -Eo '[0-9]{3,5}')
   RPM_FAND=$(echo "$SDR" | grep "FAND" | grep -Eo '[0-9]{3,5}')
   # Get    # print current Tmax, Tmean
   printf "^%-3d %5.2f" $Tmax $Tmean 
}

##############################################
# function DRIVES_check
# Print time on new log line. 
# Go through each drive, getting and printing 
# status and temp, then call function manage_data.
##############################################
function DRIVES_check {
   echo  # start new line
   TIME=$(date "+%H:%M:%S"); echo -n "$TIME  "
   Tmax=0; Tsum=0  # initialize drive temps for new loop through drives
   i=0  # count number of spinning drives
   while read LINE ; do
      get_disk_name
      $EXEPATH/sbin/smartctl -a -n standby "/dev/$DEVID" > /var/tempfile
      RETURN=$?  # have to preserve return value or it changes
      BIT0=$(($RETURN & 1))
      BIT1=$(($RETURN & 2))
      if [ $BIT0 -eq 0 ]; then
         if [ $BIT1 -eq 0 ]; then
            STATUS="*"  # spinning
         else  # drive found but no response, probably standby
            STATUS="_"
         fi
      else   # smartctl returns 1 (00000001) for missing drive
         STATUS="?"
      fi

      TEMP=""
      # Update temperatures each drive; spinners only
      if [ "$STATUS" == "*" ] ; then
         # Taking 10th space-delimited field for most SATA:
         if grep -Fq "Temperature_Celsius" /var/tempfile ; then
         	TEMP=$( cat /var/tempfile | grep "Temperature_Celsius" | awk '{print $10}')
         # Else assume SAS, their output is:
         #     Transport protocol: SAS (SPL-3) . . .
         #     Current Drive Temperature: 45 C
         elif grep -Fq "Drive Temperature" /var/tempfile ; then
         	TEMP=$( cat /var/tempfile | grep "Drive Temperature" | awk '{print $4}')
        
         # hopefully we can find our ssd:s here, this matches my old Intel drives
         # if it doesnt match yours, just keep adding more ELIF lines as needed....
         elif grep -Fq "Temperature_Internal" /var/tempfile ; then
         	TEMP=$( cat /var/tempfile | grep "Temperature_Internal" | awk '{print $10}')
         else
            TEMP="MISS"  #  we didnt get anything and setting a string here will cause the script to error out so you'll know :)
            echo "No temp found on drive /dev/"$DEVID "!!\n"
         fi
         let "Tsum += $TEMP"
         if [[ $TEMP > $Tmax ]]; then Tmax=$TEMP; fi;
         let "i += 1"
      fi
      printf "%s%-2d  " "$STATUS" $TEMP
   done <<< "$DEVLIST"
   manage_data  # manage data function
}

#####################################################
# All this happens only at the beginning
# Initializing values, list of drives, print header
#####################################################

# Check if CPU Temp is available via sysctl (will likely fail in a VM)
CPU_TEMP_SYSCTL=$(($(sysctl -a | grep dev.cpu.0.temperature | wc -l) > 0))
if [[ $CPU_TEMP_SYSCTL == 1 ]]; then
	CORES=$(($(sysctl -n hw.ncpu)-1))
fi

echo "How many whole minutes do you want between spin checks?"
read T
SEC=$(bc <<< "$T*60")			# bc is a calculator

# Get list of drives
if [ "$SYSTEM" == "Linux" ] ; then
    DEVLIST1=$($EXEPATH/bin/lsblk -d -n -o KNAME)
else
    DEVLIST1=$(/sbin/camcontrol devlist)
fi

# Remove lines with non-spinning devices; edit as needed
# You could use another strategy, e.g., find something in the camcontrol devlist 
# output that is unique to the drives you want, for instance only WDC drives:
# if [[ $LINE != *"WDC"* ]] . . .
# added zd/d to sed as lsblk includes zfs 'disks' and removed filter for Intel and SSD
#DEVLIST="$(echo "$DEVLIST1"|sed '/zd/d;/KINGSTON/d;/ADATA/d;/SanDisk/d;/OCZ/d;/LSI/d;/EXP/d;/INTEL/d;/TDKMedia/d;/SSD/d;/VMware/d;/Enclosure/d;/Card/d;/Flash/d')"
DEVLIST="$(echo "$DEVLIST1"|sed '/zd/d;/KINGSTON/d;/ADATA/d;/SanDisk/d;/OCZ/d;/LSI/d;/EXP/d;/TDKMedia/d;/VMware/d;/Enclosure/d;/Card/d;/Flash/d')"
DEVCOUNT=$(echo "$DEVLIST" | wc -l)
echo "Got" $DEVCOUNT "drives."

printf "\n%s\n%s\n%s\n" "NOTE ABOUT DUTY CYCLE (Fan%0 and Fan%1):" \
"Some boards apparently report incorrect duty cycle, and can" \
"report duty cycle for zone 1 when that zone does not exist."

# Before starting, go through the drives to report if
# smartctl return value indicates a problem (>2).
# Use -a so that all return values are available.
while read LINE ; do
   get_disk_name
   $EXEPATH/sbin/smartctl -a -n standby "/dev/$DEVID" > /var/tempfile
   if [ $? -gt 2 ]; then
      printf "\n"
      printf "*******************************************************\n"
      printf "* WARNING - Drive %-4s has a record of past errors,   *\n" $DEVID
      printf "* is currently failing, or is not communicating well. *\n"
      printf "* Use smartctl to examine the condition of this drive *\n"
      printf "* and conduct tests. Status symbol for the drive may  *\n"
      printf "* be incorrect (but probably not).                    *\n"
      printf "*******************************************************\n"
   fi
done <<< "$DEVLIST"

printf "\n%s %36s %s \n" "Key to drive status symbols:  * active;  _ standby;  ? unknown" "Version" $VERSION
print_header

###########################################
# Main loop through drives every T minutes
###########################################
while [ 1 ] ; do
	# Print header every quarter day.  Expression removes any
	# leading 0 so it is not seen as octal
	HM=$(date +%k%M); HM=`expr $HM + 0`
	R=$(( HM % 600 ))  # remainder after dividing by 6 hours
	if (( $R < $T )); then print_header; fi
	Tmax=0; Tsum=0  # initialize drive temps for new loop through drives
    DRIVES_check
    
    if [[ $CPU_TEMP_SYSCTL == 1 ]]; then    
       # Find hottest CPU core
       MAX_CORE_TEMP=0
       for CORE in $(seq 0 $CORES)
       do
           CORE_TEMP="$(sysctl -n dev.cpu.${CORE}.temperature | awk -F '.' '{print$1}')"
           if [[ $CORE_TEMP -gt $MAX_CORE_TEMP ]]; then MAX_CORE_TEMP=$CORE_TEMP; fi
       done
       CPU_TEMP=$MAX_CORE_TEMP
   else
       CPU_TEMP=$($IPMITOOL sensor get "CPU Temp" | awk '/Sensor Reading/ {print $4}')
   fi

   # Print data.  If a fan doesn't exist, RPM value will be null.  These expressions 
   # substitute a value "---" if null so printing is not messed up.  Duty cycle may be 
   # reported incorrectly by boards and they can report duty for zone 1 even if there 
   # is no such zone.

    # default string
#	printf "%6.2f %3d %5s %5s %5s %5s %5s %5d %5d %-7s" $ERRc $CPU_TEMP "${RPM_FAN1:----}" "${RPM_FAN2:----}" "${RPM_FAN3:----}" "${RPM_FAN4:----}" "${RPM_FANA:----}" $DUTY0 $DUTY1 $MODEt

    # my board
	printf "%6.2f %3d %5s %5s %5s %5s %5s %5s %5s %5s %5s %5d %5d %-7s" $ERRc $CPU_TEMP "${RPM_FAN1:----}" "${RPM_FAN2:----}" "${RPM_FAN3:----}" "${RPM_FAN4:----}" "${RPM_FANA:----}" "${RPM_FANB:----}" "${RPM_FANC:----}" "${RPM_FAND:----}" $DUTY0 $DUTY1 $DUTY2 $MODEt

    sleep $(($T*60)) # seconds between runs
done

# Logs:
#   - disk status (spinning or standby)
#   - disk temperature (Celsius) if spinning
#   - max and mean disk temperature
#   - current 'error' of Tmean from setpoint (for information only)
#   - CPU temperature
#   - RPM for FAN1-4 and FANA
#   - duty cycle for fan zones 0 and 1
#   - fan mode

# Includes disks on motherboard and on HBA. 
# Uses joeschmuck's smartctl method (returns 0 if spinning, 2 in standby)
# https://forums.freenas.org/index.php?threads/how-to-find-out-if-a-drive-is-spinning-down-properly.2068/#post-28451
# Other method (camcontrol cmd -a) doesn't work with HBA
