# Overview

Based of the work here: https://gist.github.com/alanthing/cd199758a759267c98fe.

This Docker Image takes a few environment variables to identify the source image,
the target bucket, and final image name to do an automated import of a Centos7
generic cloud image.

# Prerequisites

As stated in the source script the following steps are required in order to use
this image:

```
###############################################################################
# Pre-reqs:
# - Create service role 'vimport':
#   http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/VMImportPrerequisites.html#vmimport-service-role
# - Create policy 'vmimport' with the desired S3 bucket: 
#   http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/VMImportPrerequisites.html#vmimport-iam-permissions
# - Create IAM user, attach policy 'vmimport'
# - IAM user needs a new inline policy: Refer to policy.json in this repo
# - Create S3 bucket referenced in IAM policies
# - Create API keys for use with `aws` commands below
# - Grab CentOS URL and file name from http://cloud.centos.org/centos/7/images/
#   and enter below
# - Change any other variables as desired below
###############################################################################
```

The policy document example will need to be updated with the desired S3 bucket.

# Configuration

Some sane defaults are included in the script but you can override them as necessary
through environment variables:

`S3_BUCKET` - The S3 Bucket to store intermediate VM images.  If you don't create this
ahead of time you need to make sure your IAM credentials allow for bucket creation.

`AWS_DEFAULT_REGION` - The region to run the import operation.  The `S3_BUCKET` must
exist in this region.

`C7_RAW_URL` - The URL of the cloud image to download.

# Usage

This is expected to be run on a docker engine with injected AWS credentials:

    docker run --rm -it -e S3_BUCKET=centos-genericcloud-images \
        -e AWS_ACCESS_KEY_ID=<ACCESS_KEY_ID> \
        -e AWS_SECRET_ACCESS_KEY=<SECRET_ACCESS_KEY> \
        -e S3_BUCKET=my-personal-bucket \
        univa/centos-cloud-importer

For network efficiency it is probably best to run the container hosted on an AWS instance
as the image uploaded to S3 is 8GB.  AWS Batch, AWS ECS, or a docker enabled AWS Instance 
would be adequate.

# TODO

Add checksum verification
