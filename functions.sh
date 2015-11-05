#!/bin/bash

which aws > /dev/null 2>&1 || {
    echo "ERROR: missing aws-cli"
    echo "http://aws.amazon.com/cli/"
    exit 1
}

which jq > /dev/null 2>&1 || {
    echo "ERROR: missing jq"
    echo "http://stedolan.github.io/jq/"
    exit 1
}

createStack() {
# createStack STACKNAME TEMPLATEFILE CONFFILE
    aws cloudformation create-stack \
        --stack-name "$1" \
        --template-body "file://$2" \
        --cli-input-json "$3"
}

updateStack() {
# updateStack STACKNAME TEMPLATEFILE CONFFILE
    aws cloudformation update-stack \
        --stack-name "$1" \
        --template-body "file://$2" \
        --cli-input-json "$3"
}

deleteStack() {
# deleteStack STACKNAME
    aws cloudformation delete-stack \
        --stack-name "$1"
}

describeStack() {
# describeStack STACKNAME
    aws cloudformation describe-stacks --stack-name "$1"
}

getStackStatus () {
# getStackStatus STACKNAME
    aws cloudformation describe-stacks \
        --stack-name "$1" | jq '.Stacks[0].StackStatus' -r
}

getStackStatusReason () {
# getStackStatusReason STACKNAME
    aws cloudformation describe-stacks \
        --stack-name "$1" | jq '.Stacks[0].StackStatusReason' -r
}

rotateCursor() {
# rotateCursor SECONDS
    s="-,\\,|,/"
    for _ in $(seq "$1"); do
        for j in ${s//,/ }; do
            echo -n $j
            sleep 1
            echo -ne '\b'
        done
    done
}

waitWhileStackStatus () {
# waitWhileStackStatus STACKNAME WHILESTATUS
    stackstatus="$2"
    while [ "$stackstatus" == "$2" ]; do
        stackstatus=$(getStackStatus "$1")
        sleep 4
    done
}

waitWhileStackStatusVerbose () {
# waitWhileStackStatusVerbose STACKNAME WHILESTATUS
    echo -n "Wait while $1 state is $2"
    stackstatus="$2"
    while [ "$stackstatus" == "$2" ]; do
        stackstatus=$(getStackStatus "$1")
        echo -n "."
        rotateCursor 4
    done
    echo
}

uploadTemplatesToBucket() {
# uploadTemplatesToBucket S3URL
    jsonfiles="$(find . -name '*.json' -type f)"
    echo "$jsonfiles" | while read -r jsonfile; do
        jsonfilename=$(basename "$jsonfile")
        echo "copying $jsonfile to $1/$jsonfilename"
        aws s3 cp "$jsonfile" "$1/$jsonfilename"
    done
}

createStackAndWait() {
# createStackAndWait STACKNAME TEMPLATEFILE CONFFILE
    createStack "$1" "$2" "$3"
    waitWhileStackStatusVerbose "$1" "CREATE_IN_PROGRESS"
    stackstatus=$(getStackStatus "$1")
    if [ "${stackstatus}" == "CREATE_COMPLETE" ]; then
        echo "$1" created.
    else
        echo "$1" failed to create
        aws cloudformation describe-stack-events --stack-name "$1" --max-items 5
        exit 2
    fi
}

updateStackAndWait() {
# updateStackAndWait STACKNAME TEMPLATEFILE CONFFILE
    updateStack "$1" "$2" "$3"
    waitWhileStackStatusVerbose "$1" "UPDATE_IN_PROGRESS"
    stackstatus=$(getStackStatus "$1")
    if [ "${stackstatus}" == "UPDATE_COMPLETE" ] || [ "${stackstatus}" == "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS" ]; then
        echo "$1" updated.
    else
        echo "$1" failed to update
        aws cloudformation describe-stack-events --stack-name "$1" --max-items 5
        exit 2
    fi
}

deleteStackAndWait() {
# deleteStackAndWait STACKNAME
    deleteStack "$1"
    waitWhileStackStatusVerbose "$1" "DELETE_IN_PROGRESS"
    getStackStatus "$1" 2>&1 | grep "does not exist"
    if [ $? ]; then
        echo "$1" deleted.
    else
        echo "$1" failed to delete
        getStackStatusReason "$1"
        exit 2
    fi
}

deleteBuckets() {
# deleteBuckets BUCKET1 [BUCKET2 ..]
    for rmbucket in "${@}"; do
        echo Trying to remove "${rmbucket}"
        aws s3 rb "s3://${rmbucket}"
    done
}

deleteBucketsForce() {
# WARNING: Also removes non-empty buckets
# deleteBucketsForce BUCKET1 [BUCKET2 ..]
    for rmbucket in "${@}"; do
        echo Trying to remove "${rmbucket}"
        aws s3 rb "s3://${rmbucket}" --force
    done
}

createBuckets() {
# Rolls back on errors
# createBuckets BUCKET1 [BUCKET2 ..]
    for bucketname in "${@}"; do
        echo "Checking if ${bucketname} exists"
        err=$(aws s3 ls "s3://${bucketname}" 2>&1)
        if [ $? -eq 255 ]; then

            # Did command fail because bucket does not exist?
            echo "${err}" | grep NoSuchBucket &>/dev/null
            if [ $? -eq 0 ]; then
                echo "No such bucket. Attempting to create."
                aws s3 mb s3://"${bucketname}"
                # Save aws cli return code for later
                returncode=$?
                if [ $returncode -eq 0 ]; then
                    echo "Bucket created"
                    # Save created buckets for potential rollback
                    createdbuckets+=(${bucketname})
                else
                    echo "Failed to create bucket."
                    # Rollback: delete recently created buckets
                    deleteBuckets "${createdbuckets[@]}"
                    exit $returncode
                fi
            fi

            # Did command fail because access was denied?
            echo "${err}" | grep AccessDenied &>/dev/null
            if [ $? -eq 0 ]; then
                >&2 echo "Access denied to bucket"
                deleteBuckets "${createdbuckets[@]}"
                exit 1
            fi
        else
            echo "Bucket exists"
        fi
    done
}
