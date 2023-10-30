#!/usr/bin/bash
# spintest.sh for measuring DUTY-RPM relationship of fans.
VERSION="2020-06-17x"

# Run as superuser. See notes at end.


# fohlsso2 2023-08-06
# modified to work with linux
# line 1 still needs to be manually edited for linux/bsd path
# linux is /usr/bin/bash and bsd is /usr/local/bin/bash
# modified to work with a third fan zone and eight fans
# because my test board Supermicro X10SRG-F splits the peripheral fans into two zones

# To keep the need for user edits lower we try to have both linux and bsd stuff in here
SYSTEM=$(uname)
echo "Got system as '"$SYSTEM"'"

##############################################
#
#  Settings
#
##############################################

#################  IPMITOOL SETTING ################
# Path to ipmitool.  If you're doing VM
# you may need to add (after first quote) the following to
# remotely execute commands.
#  -H <hostname/ip> -U <username> -P <password>
# We'll let the script try to find it for you, but if that doesnt work, edit the two lines below
# IPMITOOL=/usr/local/bin/ipmitool
IPMITOOL=$(which ipmitool)
echo "Got IPMITOOL installed at '"$IPMITOOL"'."

#################  LOG SETTINGS ################
# Create logfile and sends all stdout and stderr to the log, as well as to the console.
# If you want the log in the same place as the script keep this
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
LOG=$DIR/"spintest.log"

# or if you want the log somewhere else, disable the two lines above and uncomment the one below
#LOG=/mnt/MyPool/MyDataSet/MyDirectory/spintest.log  # Change to your desired log location/name
exec > >(tee -i $LOG) 2>&1

############################################################
# function print_header
# Called after user says they are ready
############################################################

function print_header {
   echo
   DATE=$(date +"%A, %b %d, %H:%M:%S")
   echo "$DATE"

   printf "%50s %32s \n" $SPACES "___Duty%_________" "Curr_RPM_______________________________________"
   printf "%28s %9s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s \n" "MODE" "Zone0" "Zone1" "Zone2" "FANA" "FANB" "FANC" "FAND" "FAN1" "FAN2" "FAN3" "FAN4"
}

#################################################
# function read_fan_data
#################################################
function read_fan_data {

   # Read duty cycles, convert to decimal.
   # Some boards provide inaccurate duty cycle.  In that case,
   # comment out these 4 lines and we assume it is what we set.
   DUTY_0=$($IPMITOOL raw 0x30 0x70 0x66 0 0) # in hex with leading space
   DUTY_0=$((0x$(echo $DUTY_0)))  # strip leading space and decimalize
   DUTY_1=$($IPMITOOL raw 0x30 0x70 0x66 0 1)
   DUTY_1=$((0x$(echo $DUTY_1)))
   DUTY_2=$($IPMITOOL raw 0x30 0x70 0x66 0 2)  # the third zone
   DUTY_2=$((0x$(echo $DUTY_2)))

   # Read fan mode, convert to decimal, get text equivalent.
   MODE=$($IPMITOOL raw 0x30 0x45 0) # in hex with leading space
   MODE=$((0x$(echo $MODE)))  # strip leading space and decimalize
   # Text for mode
   case $MODE in
      0) MODEt="Standard" ;;
      1) MODEt="Full" ;;
      2) MODEt="Optimal" ;;
      4) MODEt="HeavyIO" ;;
   esac

   # Get reported fan speed in RPM from sensor data repository.
   # Takes the pertinent FAN line, then 3 to 5 consecutive digits
   SDR=$($IPMITOOL sdr)
   FAN1=$(echo "$SDR" | grep "FAN1" | grep -Eo '[0-9]{3,5}')
   FAN2=$(echo "$SDR" | grep "FAN2" | grep -Eo '[0-9]{3,5}')
   FAN3=$(echo "$SDR" | grep "FAN3" | grep -Eo '[0-9]{3,5}')
   FAN4=$(echo "$SDR" | grep "FAN4" | grep -Eo '[0-9]{3,5}')
   FANA=$(echo "$SDR" | grep "FANA" | grep -Eo '[0-9]{3,5}')
   FANA=$(echo "$SDR" | grep "FANA" | grep -Eo '[0-9]{3,5}')
   FANB=$(echo "$SDR" | grep "FANB" | grep -Eo '[0-9]{3,5}')
   FANC=$(echo "$SDR" | grep "FANC" | grep -Eo '[0-9]{3,5}')
   FAND=$(echo "$SDR" | grep "FAND" | grep -Eo '[0-9]{3,5}')
}

##############################################
# function print_line
#
##############################################
function print_line {
   printf "%-23s %-8s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s \n"  "$COND" $MODEt "${DUTY_0:----}" "${DUTY_1:----}" "${DUTY_2:----}" "${FANA:----}" "${FANB:----}" "${FANC:----}" "${FAND:----}" "${FAN1:----}" "${FAN2:----}" "${FAN3:----}" "${FAN4:----}"
}

#####################################################
# Main section
#####################################################
read_fan_data  # Get before script changes things
MODEorig=$MODE

echo
echo "Script to determine fan RPMs associated with varying duty cycles."
echo "Duty will be varied from 100% down in steps of 10."
echo "After setting duty, we wait 5 seconds for equilibration"
echo "before reading the fans.  Some points:"
echo
echo "1. Set the log path in the script before beginning."
echo "2. There should be no fan control scripts running."
echo "3. At very high and especially low fan speeds, the BMC may take "
echo "   over and change the duty.  You can:"
echo "     - ignore it,"
echo "     - adjust fan thresholds before testing, or"
echo "     - edit the script so it starts and/or ends at different values"
echo "       (see comment before while loop for instructions)."

# Print before test
print_header
COND="Conditions before test"
print_line

echo
echo "Are you ready to begin? (y/n)"
read START
if [ $START != "y" ]; then
   exit
fi

print_header

# Set mode to 'Full' to avoid BMC changing duty cycle
# Need to wait a tick or it may not get next command
# "echo -n" to avoid annoying newline generated in log
echo -n `$IPMITOOL raw 0x30 0x45 1 1`
sleep 1

# This loop starts at 100% duty cycle and drops by
# 10 points each step, reading fans each stop.
# To limit the low end of duty cycle test,
# edit the number after '-gt' in the following line . E.g., if you
# don't want your fans to go below 20, any number from
# 10 to 19 will stop it at 20.

i=100

while [ $i -gt 0 ]; do
   DUTY_0=$i; DUTY_1=$i; DUTY_2=$i
   echo -n `$IPMITOOL raw 0x30 0x70 0x66 1 0 $i`  # zone 0
   sleep 1
   echo -n `$IPMITOOL raw 0x30 0x70 0x66 1 1 $i`  # zone 1
   sleep 1
   echo -n `$IPMITOOL raw 0x30 0x70 0x66 1 2 $i`  # zone 2
   sleep 5
   read_fan_data
   COND="Duty cycle $i%"
   print_line
   let i=i-10
done

# Leave it in previous mode and walk away
echo -n `$IPMITOOL raw 0x30 0x45 1 $MODEorig`

