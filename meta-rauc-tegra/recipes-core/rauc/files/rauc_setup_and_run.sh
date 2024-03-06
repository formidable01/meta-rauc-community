#!/bin/sh
# This script facilitates the RAUC-based update process.
# The steps are as follows:`
#
# 1. Chunks of an update image will be transmitted to one base Orin unit
#    from the bus as they are received from the ground.
# 
# 2. Each packet will be validated by verifying a SHA or MD5 or BLAKE2S checksum 
#    and sequence number.
# 
# 2.1.Any checksum failure will be signaled by a failure message sent to the bus.
# 
# 2.2 Any missing sequence number will be noted and if still missing after all 
#     packets have been received, it will be signaled by a failure message sent to the bus.
# 
# 3. The Orin unit will validate that all packets have been received and then 
#    reconstruct the update image.
# 
# 4. An MD5 checksum will be calculated for the entire received image 
#    and verified against the expected value.
# 
# 4.1 If the checksum fails, a failure message will be returned to the bus.
# 
# 5. The correctly validated image will be installed and booted by the Orin system.
# 
# 6. If the system boots correctly, the image will be marked as active
# 
# The bus will be in charge of updating each Orin and ensuring that the Orins are all
# running the same versions
#
# Notes: 
# A. The image is received and stored in ${RAUC_RUN_ROOT}/new_image as update_image.<packet_number>
# B. The number of packets expected is stored in ${RAUC_RUN_ROOT}/new_image/expected_packets
# C. The number of packets received so far is stored in ${RAUC_RUN_ROOT}/new_image/packet_count
# D. The last packet numnber received is stored in ${RAUC_RUN_ROOT}/new_image/packet_number
# E. The expected md5sum is stored in ${RAUC_RUN_ROOT}/new_image/expected_md5sum
# F. ${RAUC_RUN_ROOT}/new_image/REBOOTED exists means the system has rebooted and is running (or should 
#    be running) a new image
# G. ${RAUC_RUN_ROOT}/new_image/BOOTEDA exists means the system is/was running image A before last reboot
# H. ${RAUC_RUN_ROOT}/new_image/BOOTEDB exists means the system is/was running image B before last reboot
# I. log file in ${RAUC_RUN_ROOT}/new_image/update.log
#
# An optimization would be to have all the Orins be system aware and include a list of all
# Orins and their IP addresses on each Orin.  This could be used for them to test the status
# of other Orins and take action if necessary. This could be facilitated by having each Orin
# include a file as described below
#
#    The list of Orins in the network is stored in ${RAUC_RUN_ROOT}/ORIN_SYSTEM_LIST. This is a CSV file
#    of the following structure per line
#    <orin `hostname`>,<ip address>,<master>N
#    The N following <master> will identify the priority selection of that orin as master
#    For instance, at time zero master1 will be the overall system master.  Should that master fail
#    master2 will take over, etc.
#    This identical list will appear in all Orins; if for some reason this needs to be changed
#    all orins will need to update their list
#
RAUC_SHARED="/eoi_shared"
RAUC_RUN_ROOT="${RAUC_SHARED}/rauc"
LOG="${RAUC_RUN_ROOT}/rauc.log"
TEST_UPDATE_PROCESS=1
#
#
# [UNUSED] parse and the list figure out if the slave or the master
#
who_is()
{
	master_or_slave = $1
	# ip addr of this system
	i_am = $(ifconfig -a eth0 | grep inet | cut -f2 -d':' | cut -f1 -d' ')
	# determine active master
	if [ $master_or_slave = "MASTER" ]; then
		echo "MASTER" >> ${LOG}
	elif [ $master_or_slave = "SLAVE" ]; then
		echo "SLAVE" >> ${LOG}
	else
		echo "ERROR: who_is() bad argument '$master_or_slave'" >> ${LOG}
	fi
}
#
# [UNUSED] parse and the list propagate the update to all other orins
#
tell_all_orins()
{
	#$1 is "BOOTA" or "BOOTB"
	echo "tell_all_orins() $1" >> ${LOG}
	if [ "$1" == "BOOTA" ]; then
		echo "BOOTA" >> ${LOG}
	elif [ "$1" == "BOOTB" ]; then
		echo "BOOTB" >> ${LOG}
        else
		echo "ERROR: tell_all_orins() : BAD BOOT SPECIFIED" >> ${LOG}
	fi	
}
#
# MAIN ENTRY POINT
#
# report where we are rauc-wise
echo `date` >> ${LOG}
rauc status >> ${LOG}
# Test if system has been initialized for use with RAUC
if [ ! -f ${RAUC_RUN_ROOT}/INITIALIZED ]; then
        echo -n `date` >> ${LOG}
	echo " Initializing" >> ${LOG}
	# ensure the directory for the new_image exists
	if [ ! -e ${RAUC_RUN_ROOT}/new_image ]; then
	    mkdir ${RAUC_RUN_ROOT}/new_image
	fi
	# set up "fake" UEFI entries to associate A and B labels with boot
	# images in RAUC conf file
	check=$(efibootmgr -v | grep "* A" | grep BOOT)
	if [ "$check" == "" ]; then
		efibootmgr --create --disk /dev/mmcblk0 --part 1 --label A --loader \\EFI\\BOOT\\bootaa64.efi
	fi
	check=$(efibootmgr -v | grep "* B" | grep BOOT)
	if [ "$check" == "" ]; then
		efibootmgr --create --disk /dev/mmcblk0 --part 2 --label B --loader \\EFI\\BOOT\\bootaa64.efi
	fi
	# setup correct extlinux.conf file
	# with default as A (primary) or B (secondary) boot
	if [ ! -f /boot/extlinux/extlinux.conf.A ]; then
	    cp /boot/extlinux/extlinux.conf /boot/extlinux/extlinux.conf.A
	fi
	if [ ! -f /boot/extlinux/extlinux.conf.B ]; then
	    sed 's/DEFAULT primary/DEFAULT secondary/' /boot/extlinux/extlinux.conf > /boot/extlinux/extlinux.conf.B
	fi
	touch ${RAUC_RUN_ROOT}/INITIALIZED
fi
# Test if the system has rebooted after installing a new image
if [ -f ${RAUC_RUN_ROOT}/REBOOTED ]; then
        echo -n `date` >> ${LOG}
	echo " REBOOTED!" >> ${LOG}
	# was the install successful?
	# Slot A
	# an empty string is not true
	ISABOOTED=$(rauc status | grep "booted" | grep "mmcblk0p1")
	# 0 if it exists; 1 if it doesn't
	WASABOOTED=$([ -f ${RAUC_RUN_ROOT}/BOOTEDA ] ; echo $? )
	# Slot B
	# an empty string is not true
	ISBBOOTED=$(rauc status | grep "booted" | grep "mmcblk0p2")
	# 0 if it exists; 1 if it doesn't
	if [ "$ISABOOTED" != "" ] && [ $WASBBOOTED  == 0 ]; then
                echo "Was B...Now A" >> ${LOG}
		rm -f ${RAUC_RUN_ROOT}/BOOTEDB
		touch ${RAUC_RUN_ROOT}/BOOTEDA
		rauc status mark-good
		BOOT="BOOTA"
		tell_all_orins $BOOT
	elif [ "$ISBBOOTED" != "" ] && [ $WASABOOTED == 0 ]; then
                echo "Was A...Now B" >> ${LOG}
		rm -f ${RAUC_RUN_ROOT}/BOOTEDA
		touch ${RAUC_RUN_ROOT}/BOOTEDB
		rauc status mark-good
		BOOT="BOOTB"
		tell_all_orins $BOOT
	else
                echo "ERROR: Bad boot" >> ${LOG}
		# we have a bad boot situation
		rauc status mark-bad
	fi
	# if it was then let the other Orins know
	# they should update if you are the master Orin
	# log the event (success of fail of reboot)
	rm -f ${RAUC_RUN_ROOT}/REBOOTED
fi
# Proceed along with the normal behavior
# Here we check the system state and update
# the status indicators
ISABOOTED=$(rauc status | grep "booted" | grep "mmcblk0p1")
if [ "$ISABOOTED" != "" ]; then
    touch ${RAUC_RUN_ROOT}/BOOTEDA
    rm -f ${RAUC_RUN_ROOT}/BOOTEDB
    rauc status mark-good
fi
ISBBOOTED=$(rauc status | grep "booted" | grep "mmcblk0p2")
if [ "$ISBBOOTED" != "" ]; then
    touch ${RAUC_RUN_ROOT}/BOOTEDB
    rm -f ${RAUC_RUN_ROOT}/BOOTEDA
    rauc status mark-good
fi
#
while  [ 1 ]
do
	# every minute - check things out
	sleep 60
#        echo -n `date` >> ${LOG}
#	echo " Checking for update..." >> ${LOG}
	if [ -n "${TEST_UPDATE_PROCESS+set}" ]; then
            echo "Testing update process" >> ${LOG}
	    # The working assumption is that the image file is 
	    # transferred first and then the MD5 file is moved
	    # to this system. Because the image file is larger
	    # we make sure it's all there before starting operations
	    # with it
	    if [ -f ${RAUC_RUN_ROOT}/new_image/update_image.md5 ] ; then
                echo -n `date` >> ${LOG}
		echo ": found update_image.md5" >> ${LOG}
	        # we've got a possible update file
		# check for the md5 checksum
	        if [ -f ${RAUC_RUN_ROOT}/new_image/update_image ] ; then
                    echo -n `date` >> ${LOG}
		    echo ": found update_image" >> ${LOG}
		    # read and check md5
		    actual=$(md5sum ${RAUC_RUN_ROOT}/new_image/update_image | awk '{print $1}')
		    expected=$(awk '{print $1}' ${RAUC_RUN_ROOT}/new_image/update_image.md5)
		    if [ "${actual}" == "${expected}" ]; then
                        echo -n `date` >> ${LOG}
		        echo ": starting update" >> ${LOG}
	                # save off the file information
	                rauc info ${RAUC_RUN_ROOT}/new_image/update_image >> ${LOG}
	                # install the file
	                time rauc install ${RAUC_RUN_ROOT}/new_image/update_image >> ${LOG}
	                if [ $? == 0 ]; then
		            # remove the update file
		            rm -rf ${RAUC_RUN_ROOT}/new_image/update_image
		            rm -rf ${RAUC_RUN_ROOT}/new_image/update_image.md5
	                    # set up for reboot
	                    ABOOTED=$([ -f ${RAUC_RUN_ROOT}/BOOTEDA ] ; echo $? )
	                    BBOOTED=$([ -f ${RAUC_RUN_ROOT}/BOOTEDB ] ; echo $? )
		            # setup to reboot eith correct image selected
		            if [ $ABOOTED == 0 ] ; then
		                cp /boot/extlinux/extlinux.conf.B /boot/extlinux/extlinux.conf
		            fi
		            if [ $BBOOTED == 0 ] ; then
		                cp /boot/extlinux/extlinux.conf.A /boot/extlinux/extlinux.conf
		            fi
	                    touch ${RAUC_RUN_ROOT}/REBOOTED
			    # A new image may require re-initialization of
			    # boot process so we make sure that happens
                            rm -f ${RAUC_RUN_ROOT}/INITIALIZED
		            sync
		            reboot
		        else
                            echo -n `date` >> ${LOG}
                            echo ": Install process failed" >> ${LOG}
		            # remove the update file
		            rm -rf ${RAUC_RUN_ROOT}/new_image/update_image
		            rm -rf ${RAUC_RUN_ROOT}/new_image/update_image.md5
		            # keep waiting for a new file
		        fi
	            else
                        echo -n `date` >> ${LOG}
                        echo ": MD5 check failed" >> ${LOG}
		        # remove the update file
		        rm -rf ${RAUC_RUN_ROOT}/new_image/update_image
		        rm -rf ${RAUC_RUN_ROOT}/new_image/update_image.md5
		        # keep waiting for a new file
		    fi    
		else
                    echo -n `date` >> ${LOG}
                    echo ": No MD5 file provided" >> ${LOG}
		    # remove the update file
		    rm -rf ${RAUC_RUN_ROOT}/new_image/update_image
		    rm -rf ${RAUC_RUN_ROOT}/new_image/update_image.md5
		    # keep waiting for a new file
                fi
#	    else
#		echo "Nothing to update" >> ${LOG}
	    fi
        else
	    # this section of code is supposed to assemble chunks of an update file
	    # as received into a complete image suitable for actual update
	    # TODO: it remains to to be tested and verified
	    next_update_image = "${RAUC_RUN_ROOT}/new_image/update_image."
       	    # test to see if a new file packet has arrived
	    while read LINE; do next_packet_number = $(echo "$LINE" | cut -f1 -d"\n"); done < ${RAUC_RUN_ROOT}/new_image/packet_number
	    # get the expected number of packets that should arrive in total
	    while read LINE; do expected_packets = $(echo "$LINE" | cut -f1 -d"\n"); done < ${RAUC_RUN_ROOT}/new_image/expected_packets
	    # build the file name for the expected fragement
	    next_update_image = eval "\$next_update_image\$next_packet_number"
	    # check if the fragement has arrived
	    if [ -f $next_update_image ]; then
		# add the fragment to the full image file
		cat $next_update_image >> ${RAUC_RUN_ROOT}/new_image/update_image
		echo "INFO: packet numbers : next_packet_number: '$next_packet_number' expected_packets: '$expected_packets'" >> ${LOG}
		if [ $next_packet_number = $expected_packets ]; then
			# we've got all the packets
			# verify the md5sum
			while read LINE; do EXPECTED_MD5SUM = $(echo "$LINE" | cut -f1 -d"\n"); done < ${RAUC_RUN_ROOT}/new_image/expected_md5sum
			# calculate the checksum, grab the first field from the returned result
			CALC_MD5SUM=$(md5sum ${RAUC_RUN_ROOT}/new_image/update_image | cut -f1 -d" ")
		        echo "INFO: md5sum : calculated: '$CALC_MD5SUM' expected: '$EXPECTED_MD5SUM'" >> ${LOG}
			if [ "$EXPECTED_MD5SUM" == "$CALC_MD5SUM" ]; then
			   # we've got a good update file
			   # save off the file information
			   rauc info ${RAUC_RUN_ROOT}/new_image/update_image
			   # install the file
			   time rauc install ${RAUC_RUN_ROOT}/new_image/update_image
			   if [ $? == 0 ]; then
			       # set up for reboot
	                       touch ${RAUC_RUN_ROOT}/REBOOTED
			   fi
			else
		           echo "ERROR: md5sum mismatch : calculated: '$CALC_MD5SUM' expected: '$EXPECTED_MD5SUM'" >> ${LOG}
			fi
		else
			# indicate the next packet number we expect to see
			$next_packet_number = $next_packet_number + 1
			echo $next_packet_number > ${RAUC_RUN_ROOT}/new_image/packet_number
		fi
	    fi
	fi
done
