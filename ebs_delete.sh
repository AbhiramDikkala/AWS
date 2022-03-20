echo -e "##########  Deleting old Snapshots  ##########\n"

snap_ids=`aws ec2 describe-snapshots --snapshot-ids --filters Name=tag:Name,Values=delete_later --output text --query "Snapshots[*].SnapshotId"`
for snapid in $snap_ids
do
        snap_state=`aws ec2 describe-snapshots --snapshot-ids $snapid --output text --query "Snapshots[*].State"`
        if [ "${snap_state}" == "completed" ]
        then
                `aws ec2 delete-snapshot --snapshot-id $snapid`
                echo -e "Snapshot $snapid deleted successfully..\n"
        else
                echo -e "Snapshot $snap_id not in completed state\n"
        fi
done



echo -e "##########  Deleting Old Volumes  ##########\n"


volume_ids=`aws ec2 describe-volumes --filters Name=tag:Name,Values=delete_later --output text --query "Volumes[*].VolumeId"`
for unencrypted_volume_id in $volume_ids
do
        volume_state=`aws ec2 describe-volumes --volume-ids $unencrypted_volume_id --output text --query "Volumes[*].State"`
        if [ "${volume_state}" == "available" ]
        then
                `aws ec2 delete-volume --volume-id $unencrypted_volume_id`
                echo -e "Volume $unencrypted_volume_id deleted successfully..\n"
        else
                echo -e "Volume $unencrypted_volume_id not in available state \n"
        fi
done
