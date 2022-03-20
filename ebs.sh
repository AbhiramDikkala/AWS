`sudo yum install jq -y 2&> /dev/null`
echo -e "Please Enter instance-ids [ Note: For Multiple ids include space in between (ex:id1 id2 id3)\n"
read -a ids
#echo ${#ids[@]}



for instance_id in ${ids[@]}
do
        echo "-------------------------------"
        echo -e "-------------------------------\n"
        echo -e "checking for ${instance_id}...\n"
        echo "-------------------------------"
        echo -e "-------------------------------\n"


        volume_ids=$(aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=$instance_id Name=encrypted,Values=false --output json --query "Volumes[*].VolumeId[]"| jq -r '.[]')


        inst_state(){
                instance_state=`aws ec2 describe-instances --instance-id $instance_id --output text --query "Reservations[].Instances[].State[].Name"`
        }


        if [ "$volume_ids" != "" ]
        then
                echo -e "##########################\n"
                echo $(echo -n "unencrypted Volume ids: $volume_ids")
                echo " "

                inst_state
                if [ "${instance_state}" == "running" ]
                then
                        stop_instance=`aws ec2 stop-instances --instance-ids $instance_id`
                        echo -e "##########################\n"
                        echo -e "######### stopping instance ${instance_id}... #########\n"
                        `aws ec2 wait instance-stopped --instance-ids $instance_id`
                        echo -e "Instance $instance_id stopped Successfully...\n"
                        echo -e "##########################\n"
                else
                        echo -e "##########################\n"
                        echo -e "Insatnce $instance_id already in stopped state...\n"
                        echo -e "##########################\n"
                fi



                for unencrypted_volume_id in $volume_ids
                do
                        echo -e "...............................................\n"
                        echo "########## $unencrypted_volume_id in progress... ##########"
                        echo -e "...............................................\n"

                        volume_state=`aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output text --query "Volumes[*].State" 2> /dev/null`
                        if [ $(echo $?) == 0 ]
                        then
                                tags=`aws ec2 describe-tags --filters "Name=resource-id,Values=$unencrypted_volume_id" --output json --query 'Tags[].{Key: Key, Value: Value}' > tags-${unencrypted_volume_id}.txt`
                                echo "$(cat tags-${unencrypted_volume_id}.txt)"
                                `rm -rf tags-${unencrypted_volume_id}.txt`
                                echo " "


                                availability_zone=$(aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output json --query "Volumes[*].AvailabilityZone"| jq -r '.[]')
                                echo -e "Availability zones: $availability_zone\n"
                                region=`echo $availability_zone | sed 's/.$//'`
                                echo -e "Region: $region\n"


                                device=$(aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output json --query "Volumes[*].Attachments[].Device" |jq -r '.[]')
                                echo -e "Device_type: $device\n"


                                volume_type=$(aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output json --query "Volumes[*].VolumeType" | jq -r '.[]')
                                echo -e "VolumeType: $volume_type\n"


                                volume_size=$(aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output json --query "Volumes[*].Size" | jq -r '.[]')
                                echo -e "Volumesize: ${volume_size}Gb\n"


                                iops=$(aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output text --query "Volumes[*].Iops[]")
                                echo -e "Iops: $iops\n"


                                delete_on_termination=$(aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output text --query "Volumes[*].Attachments[].DeleteOnTermination")
                                echo -e "Delete-on-Termination : $delete_on_termination\n"

                                echo -e "##########################\n"
                                volume_state=`aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output text --query "Volumes[*].State" 2> /dev/null`
                                if [ $(echo $?) == 0 ]
                                then
                                        echo -e "######## creating snapshot.... ########\n"


                                        snap_id=`aws ec2 create-snapshot --volume-id $unencrypted_volume_id --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=delete_later}]' --output json | grep SnapshotId`
                                        snapshot_id=`echo "{$snap_id}" | jq -r '.[]'`


                                        `aws ec2 wait snapshot-completed  --snapshot-ids $snapshot_id`
                                        echo -e "Snaphotid: $snapshot_id\n"
                                        echo -e "####### Snapshot creation completed... #######\n"

                                        echo -e "##########################\n"

                                        snap_copy_id=`aws ec2 copy-snapshot --region $region --source-region $region --encrypted --source-snapshot-id $snapshot_id --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=delete_later}]'`



                                        copy_snapshot_id=`echo $snap_copy_id | jq -r '."SnapshotId"'`



                                        echo -e "####### Copying snapshot.... #######\n"
                                        `aws ec2 wait snapshot-completed  --snapshot-ids $copy_snapshot_id`
                                        echo -e "Copy Snapshotid: $copy_snapshot_id\n"

                                        echo -e "##########################\n"


                                        if [ "${volume_type}" == "gp3" ] || [ "${volume_type}" == "io1" ] || [ "${volume_type}" == "io2" ]
                                        then
                                                encrypted_volume_id=`aws ec2 create-volume --region $region --availability-zone $availability_zone --snapshot-id $copy_snapshot_id --volume-type $volume_type --size $volume_size --iops $iops --encrypted --output text --query "VolumeId"`
                                        else
                                                encrypted_volume_id=`aws ec2 create-volume --region $region --availability-zone $availability_zone --snapshot-id $copy_snapshot_id --volume-type $volume_type --size $volume_size --encrypted --output text --query "VolumeId"`
                                        fi


                                        echo -e "####### creating volume.... #######\n"
                                        `aws ec2 wait volume-available --volume-ids $encrypted_volume_id`
                                        echo -e "Encrypted volume Id: $encrypted_volume_id\n"

                                        echo -e "##########################\n"


                                        tag_value=`aws ec2 describe-tags --filters "Name=resource-id,Values=$unencrypted_volume_id" --output json --query 'Tags[].Value' > Value-${unencrypted_volume_id}.json`
                                        `jq -r < Value-${unencrypted_volume_id}.json '.[]' > Value-${unencrypted_volume_id}.txt`

                                        value_array=()
                                        while read -r line;
                                        do
                                                #echo $line
                                                value_array+=("$(echo $line)")
                                        done < Value-${unencrypted_volume_id}.txt


                                        tag_key=`aws ec2 describe-tags --filters "Name=resource-id,Values=$unencrypted_volume_id" --output json --query 'Tags[].Key' > Key-${unencrypted_volume_id}.json`
                                        `jq -r < Key-${unencrypted_volume_id}.json '.[]' > Key-${unencrypted_volume_id}.txt`

                                        key_array=()

                                        while read -r line;
                                        do
                                                #echo $line
                                                key_array+=("$(echo $line)")
                                        done < Key-${unencrypted_volume_id}.txt


                                        count=${#value_array[@]}
                                        #echo $count

                                        echo -e "##########################\n"

                                        echo -e "############   Adding Tags...  ###########\n"
                                        
                                        `rm -rf Value-${unencrypted_volume_id}.json`
                                        `rm -rf Value-${unencrypted_volume_id}.txt`
                                        `rm -rf Key-${unencrypted_volume_id}.json`
                                        `rm -rf Key-${unencrypted_volume_id}.txt`
                                        
                                        i=0
                                        while [ $i -lt $count ]
                                        do
                                                echo "Key is ${key_array[$i]} , Value is ${value_array[$i]}"
                                                `aws ec2 create-tags --resources $encrypted_volume_id --tags Key="${key_array[$i]}",Value="${value_array[$i]}"`
                                                ((i++))
                                        done

                                        echo " "
                                        echo -e "####### Added Tags Successfully... #######\n"

                                        echo -e "##########################\n"
                                else
                                        echo -e "Volume $unencrypted_volume_id doesn't exist"
                                fi
                                inst_state
                                if [ "${instance_state}" == "stopped" ]
                                then
                                        detach_volume=`aws ec2 detach-volume --volume-id $unencrypted_volume_id`
                                        echo -e "####### detaching volume $unencrypted_volume_id ... #######\n"
                                        `aws ec2 wait volume-available --volume-ids $unencrypted_volume_id`
                                        echo -e "Volume $unencrypted_volume_id detached successfully...\n"

                                        echo -e "##########################\n"
                                        attach_volume=`aws ec2 attach-volume --volume-id $encrypted_volume_id --instance-id $instance_id --device $device`
                                        echo -e "####### attaching volume $encrypted_volume_id ...#######\n"
                                        `aws ec2 wait volume-in-use --volume-ids $encrypted_volume_id`
                                        echo -e "####### Volume $encrypted_volume_id attached successfully.. ########\n"


                                        if [ "${delete_on_termination}" == "False" ]
                                        then
                                                `aws ec2 modify-instance-attribute --instance-id $instance_id --block-device-mappings "[{\"DeviceName\": \"${device}\" , \"Ebs\" : {\"DeleteOnTermination\":false}}]"`
                                        else
                                                `aws ec2 modify-instance-attribute --instance-id $instance_id --block-device-mappings "[{\"DeviceName\": \"${device}\" , \"Ebs\" : {\"DeleteOnTermination\":true}}]"`
                                        fi
                                fi


                                `aws ec2 create-tags --resources $unencrypted_volume_id --tags Key=Name,Value=delete_later`

                                echo -e "...............................................\n"
                                echo "############ $unencrypted_volume_id completed... ###########"
                                echo -e "...............................................\n"
                        else
                                echo -e "volume $unencrypted_volume_id doesn't exist\n"
                        fi
                done




                        inst_state
                        if [ "${instance_state}" == "stopped" ]
                        then
                                echo -e "##########################\n"
                                start_insatnce=`aws ec2 start-instances --instance-ids $instance_id`
                                echo -e "######### starting instance ${instance_id}... #########\n"
                                `aws ec2 wait instance-running --instance-ids $instance_id`
                                echo -e "$instance_id started successfully...\n"
                                echo -e "##########################\n"
                        fi


                        echo "---------------------------------------"
                        echo -e "---------------------------------------\n"
                        echo -e "Completed for ${instance_id}....\n"
                        echo "---------------------------------------"
                        echo -e "---------------------------------------\n"

                else
                        echo "......................................................"
                        echo -e "......................................................\n"
                        echo -e "No unencrypted Volumes Found for ${instance_id}!!!\n"
                        echo "......................................................"
                        echo -e "......................................................\n"
                fi

done
