 <#
.SYNOPSIS
    Deploys MSBuild result to S3 Bucket.

.DESCRIPTION
    Creates zip bundle, pushes it to a bucket, runs deploy and monitors status of the deployment.

.PARAMETER s3bucket
    S3 bucket name.

.PARAMETER s3prefix
    S3 prefix for bundle in the bucket push operation.

.PARAMETER applicationName
    S3 Name of the application, that name will be used to create a zip archive.

.PARAMETER deploymentGroupName
    S3 Deplotment group name.

.PARAMETER pollingTimeoutSec
    How much script awaits for success status. Default is 1200s

.PARAMETER pollingFreqSec
    How much script awaits for the next try to fetch deployment info. Default is 30s

.PARAMETER msbuildPublishPath
    Path of the MSBuild result.

.PARAMETER AWS_PROFILE
    Specifies an AWS access key associated with an IAM account.

.PARAMETER AWS_DEFAULT_REGION
    The Default region name identifies the AWS Region whose servers you want to send your requests to by default.

.PARAMETER AWS_DEFAULT_OUTPUT
    Specifies the output format to use.


.EXAMPLE
    .\AwsCodeDeploy.ps1 -s3bucket bucket `
                        -s3prefix somePrefix `
                        -applicationName name `
                        -deploymentGroupName groupName `
                        -pollingTimeoutSec 90 `
                        -pollingFreqSec 5 `
                        -msbuildPublishPath \bin\ `
                        -AWS_PROFILE name `
                        -AWS_DEFAULT_REGION DREG `
                        -AWS_DEFAULT_OUTPUT TEXT
.NOTES

#>
param(
    $s3bucket,
    $s3prefix="$ENV:JOB_NAME/$ENV:BUILD_NUMBER",
    $applicationName="steblynskyi",
    $deploymentGroupName,
    $pollingTimeoutSec=1200,
    $pollingFreqSec=30,
    $msbuildPublishPath="$ENV:WORKSPACE\bin",
    $AWS_DEFAULT_REGION="us-east-1",
    $AWS_DEFAULT_OUTPUT="json",
    $AWS_PROFILE
)

$ErrorActionPreference = "Stop"

if($null -eq $AWS_PROFILE){ Write-Host "AWS_PROFILE is not provided and will be used from the default" }
else{ $Env:AWS_PROFILE=$AWS_PROFILE }

$Env:AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
$Env:AWS_DEFAULT_OUTPUT=$AWS_DEFAULT_OUTPUT

function Join-Url {
    param (
        $Path,
        $ChildPath
    )
    if ($Path.EndsWith('/')) {
        return "$Path"+"$ChildPath"
    }
    else {
        return "$Path/$ChildPath"
    }
}

function Get-Deployment-Info {
    param(
        $deploymentId
    )

    $deploymentJson = aws deploy get-deployment --output="json" --deployment-id=$deploymentId

    if($null -eq $deploymentJson)
    {
        return $null
    }

    return (ConvertFrom-Json "$deploymentJson").deploymentInfo
}

function Get-Deployment-Instances {
    param(
        $deploymentId
    )

    $instancesJson = aws deploy list-deployment-instances --output="json" --deployment-id=$deploymentId

    if($null -eq $instancesJson)
    {
        return $null
    }

    return (ConvertFrom-Json "$instancesJson").instancesList
}

Write-Host "Starting AwsCodeDeploy: $(Get-Date)"

Write-Host "Files location for zipping $msbuildPublishPath"

Set-Location -Path $msbuildPublishPath

$key = Join-Url $s3prefix "$ENV:BUILD_NUMBER-$applicationName.zip"
$bucketUrl = "s3://$(Join-Url $s3bucket $key)"

Write-Host "Uploading zip to $bucketUrl"

$pushResult = aws deploy push --application-name=$applicationName `
                              --s3-location=$bucketUrl `
                              --ignore-hidden-files

if($null -eq $pushResult)
{
    throw "aws deploy push is failed"
}

Write-Host "Registering revision for application $applicationName"

$deploymentResultJson = aws deploy create-deployment --output="json" `
                                                     --application-name=$applicationName `
                                                     --deployment-config-name=CodeDeployDefault.OneAtATime `
                                                     --deployment-group-name=$deploymentGroupName `
                                                     --s3-location=bucket=$s3bucket,bundleType=zip,key=$key

Write-Host "Deployment has been created: $deploymentResultJson"

$deploymentId = (ConvertFrom-Json "$deploymentResultJson").deploymentId

#Deployment monitoring

$deploymentStartTime = Get-Date
$deploymentNowTime = $deploymentStartTime

Write-Host "Monitoring deployment with ID $deploymentId. TotalTimeout: $pollingTimeoutSec. Frequency: $pollingFreqSec"

$firstLoop = $true

while (($deploymentNowTime - $deploymentStartTime).TotalSeconds -lt $pollingTimeoutSec ){

    Start-Sleep $pollingFreqSec

    if($firstLoop)
    {
        $deploymentInstances = Get-Deployment-Instances $deploymentId
        $firstLoop = $false
        Write-Host "Instances: $deploymentInstances"
    }

    $deploymentInfo = Get-Deployment-Info $deploymentId

    Write-Host "Deployment Status: $($deploymentInfo.status); $($deploymentInfo.deploymentOverview)"

    if(-not($null -eq $deploymentInfo) -and
       ($deploymentInfo.status -eq "Failed" -or $deploymentInfo.status -eq "Skipped"))
    {
        throw "Build failed, status: $($deploymentInfo.status)"
    }elseif(-not($null -eq $deploymentInfo) -and $deploymentInfo.status -eq "Succeeded")
    {
        Write-Host "Deployment is succeeded. Time: $($deploymentInfo.completeTime)"
        Exit
    }

    $deploymentNowTime = Get-Date
}

throw "Deployment timeout is exceeded."