#!/bin/bash

# Exit immediately upon a non-zero status
set -e
set -x



###############################################################################
# Pre-reqs:
# - Create service role 'vimport':
#   http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/VMImportPrerequisites.html#vmimport-service-role
# - Create policy 'vmimport' with the desired S3 bucket: 
#   http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/VMImportPrerequisites.html#vmimport-iam-permissions
# - Create IAM user, attach policy 'vmimport'
# - IAM user needs a new inline policy with "ec2:CopyImage", "ec2:DeleteSnapshot",
#   "ec2:DeregisterImage", and "ec2:DescribeImages" via the following JSON:
#   {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:CopyImage","ec2:DeleteSnapshot","ec2:DeregisterImage","ec2:DescribeImages"],"Resource":"*"}]}
# - Create S3 bucket referenced in IAM policies
# - Create API keys for use with `aws` commands below
# - Grab CentOS URL and file name from http://cloud.centos.org/centos/7/images/
#   and enter below
# - Change any other variables as desired below
###############################################################################


# Set this to the bucket you'll be using
S3_BUCKET="${S3_BUCKET:-bucket-name}"

# Working region- you can copy the AMI to other regions later
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-west-2}"

# CentOS 7 raw archive URL...
C7_RAW_URL="${C7_RAW_URL:-https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1809.raw.tar.gz}"
# From... https://cloud.centos.org/centos/7/images/sha256sum.txt
C7_RAW_CHECKSUM="${C7_RAW_CHECKSUM:-d7b4debec1edbdda0e5e68d18daf47800fd77a9e3775e43496dbb9e53ff6cbe3}"

# AMI Name
AMI_NAME="CentOS Linux 7.5.1809 x86_64 HVM EBS"

# AMI Description
AMI_DESC="Imported from $C7_RAW_URL without modification"



# Download file
curl \
  --remote-name \
  "$C7_RAW_URL"
# Extract raw file, remove 4 unnecessary folder names in archive
tar xzvf "$( basename $C7_RAW_URL )"

C7_RAW_FILENAME="$( ls CentOS-7-x86_64*.raw )"

# Create bucket if it doesn't exist
aws \
  s3api \
  head-bucket \
  --bucket "$S3_BUCKET" 2>/dev/null \
  || \
  aws \
    s3api \
    create-bucket \
    --bucket "$S3_BUCKET" \
    --query "Location" --output text

# copy file to s3 bucket
aws \
  s3 \
  cp \
  "$C7_RAW_FILENAME" \
  "s3://${S3_BUCKET}/${C7_RAW_FILENAME}"

# Create AMI from raw file
ImportTaskIdImage=$(
  aws \
    ec2 \
    import-image \
    --architecture "x86_64" \
    --platform "Linux" \
    --role-name "vmimport" \
    --disk-containers "UserBucket={S3Bucket=${S3_BUCKET},S3Key=${C7_RAW_FILENAME}}" \
    --query "ImportTaskId" --output text
 )

# Check status
aws ec2 describe-import-image-tasks --import-task-ids "$ImportTaskIdImage"

set +x

# Wait until completed
ImportTaskIdImageStatus=""
until [[ $ImportTaskIdImageStatus == "completed" ]]; do
  sleep 3
  echo -n "."

  ImportTaskIdImageStatus=$(
    aws \
      ec2 \
      describe-import-image-tasks \
      --import-task-ids "$ImportTaskIdImage" \
      --query "ImportImageTasks[0].Status" --output text
    )
done
echo

set -x

# Delete source file in S3
aws \
  s3 \
  rm \
  "s3://${S3_BUCKET}/${C7_RAW_FILENAME}"

# Get AMI once completed
ImportedAmi=$( 
  aws \
    ec2 \
    describe-import-image-tasks \
    --import-task-ids "$ImportTaskIdImage" \
    --query "ImportImageTasks[0].ImageId" --output text 
  )

# Get the imported Snapshot ID
ImportedSnapshotId=$(
  aws \
    ec2 \
    describe-import-image-tasks \
    --import-task-ids "$ImportTaskIdImage" \
    --query "ImportImageTasks[0].SnapshotDetails[0].SnapshotId" --output text 
  )

# Tag imported AMI and associated snapshot, potentially useful in Cost Reports
aws \
  ec2 \
  create-tags \
  --resources "$ImportedAmi" \
  --tags "Key=Name,Value='${AMI_NAME} - Imported'"
aws \
  ec2 \
  create-tags \
  --resources "$ImportedSnapshotId" \
  --tags "Key=Name,Value='${AMI_NAME} - Imported - Snapshot'"

# Use `aws ec2 copy-image` to add Name and Description
CopiedAmi=$(
  aws \
    ec2 \
    copy-image \
    --source-region "$AWS_DEFAULT_REGION" \
    --source-image-id "$ImportedAmi" \
    --region="$AWS_DEFAULT_REGION" \
    --name "$AMI_NAME" \
    --description "$AMI_DESC" \
    --no-encrypted \
    --query "ImageId" \
    --output text
  )

# Check status
aws ec2 describe-images --image-ids "$CopiedAmi"

set +x

# Wait for AMI to be available
CopiedAmiStatus=""
until [[ $CopiedAmiStatus == "available" ]]; do
  sleep 3
  echo -n "."

  CopiedAmiStatus=$(
    aws \
      ec2 \
      describe-images \
      --image-ids "$CopiedAmi" \
      --query "Images[0].State" --output text
  )
done
echo

set -x

# Get the copied Snapshot ID
CopiedSnapshotId=$(
  aws \
    ec2 \
    describe-images \
    --image-ids "$CopiedAmi" \
    --query "Images[0].BlockDeviceMappings[0].Ebs.SnapshotId" --output text 
  )

# Tag copied AMI and associated snapshot
aws \
  ec2 \
  create-tags \
  --resources "$CopiedAmi" \
  --tags "Key=Name,Value='${AMI_NAME}'"
aws \
  ec2 \
  create-tags \
  --resources "$CopiedSnapshotId" \
  --tags "Key=Name,Value='${AMI_NAME} - Snapshot'"

# Deregister imported AMI
aws \
  ec2 \
  deregister-image \
  --image-id "$ImportedAmi"

# Delete imported snapshot
aws \
  ec2 \
  delete-snapshot \
  --snapshot-id "$ImportedSnapshotId"
