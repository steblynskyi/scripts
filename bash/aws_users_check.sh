#!/bin/bash
################################################################################
# Help                                                                         #
################################################################################


Help()
{
   # Display Help
   echo " This script creates list of steblynskyi owned IAM users and Roles which last activity is more than x amount of days."
   echo
   echo "Syntax: scriptTemplate [-h|help|c|p|u|r]"
   echo "options:"
   echo "h,-help     Print this Help."
   echo "p           enter the AWS profile. Will use your default profile if no profile is entered (Ex: -p steblynskyi) \n"
   echo "u           Prints list of IAM users, *interger needed*."
   echo "            Enter an number to specify list the amount days since an IAM user's last activity (Web Console)(Ex: -u 30). \n "
   echo "r           Prints list of Roles \n"
   echo "            Enter an interger to specify the amount of days since role's last activity (Ex: -r 30)"
   echo "Tip: Entering the number 0 will list all contents of the given field (i.e. all user or roles). \n Lists can be print together (Ex: -u 30 -k 15 -r 1)"

}






Today=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

####################################################################################
##The list of all the users who haven't accessed the AWS Console in x amount of days
####################################################################################

function CheckAccesskeysAge(){
	finalAccessKeyAge=9999
	eachKeyAge=9999
	for accessKey in $accessKeyIds;
	do
		accessKeyLastUsed=$(aws iam get-access-key-last-used --access-key-id "$accessKey" --profile "$profile" --output json |jq 'select(.AccessKeyLastUsed != null) | .AccessKeyLastUsed |  .LastUsedDate ' | tr -d '"')
		if [[ "$accessKeyLastUsed" != null ]]
                then
                    eachKeyAge=$(( ($(date +%s) - $(date --date=$accessKeyLastUsed +%s)) / 86400 ))
                else
                    eachKeyAge=9999
                fi
		if [[ $eachKeyAge -le $finalAccessKeyAge ]]
		then
			finalAccessKeyAge=$eachKeyAge
		fi
	done
}



CallIAMUsers(){
    printf "The list of all the users who haven't accessed the AWS Console or Access key ids in the last $days days.\n"
    printf "**********************************************************************************************************\n \n"
    printf '%-20s %-15s %-15s %-15s %-50s \n' "User Name" "Created Age" "Logged In Age" "Access Key Age" "Note"
        aws iam list-users  --profile "$profile" --output json | jq -c '.Users[]' |  while read eachuser; do 
	username=$(echo $eachuser | jq -rc '.UserName')
	lastLogin=$(echo $eachuser | jq -rc '.PasswordLastUsed')
	createdOn=$(echo $eachuser | jq -rc '.CreateDate')
	accessKeyIds=$(aws iam list-access-keys --user-name "$username"  --profile "$profile"  --output json |jq '.AccessKeyMetadata[] |  .AccessKeyId' | tr -d '"')
	createdAge=$(( ($(date +%s) - $(date --date=$createdOn +%s)) / 86400 ))
	if [[ "$lastLogin" == null ]] #User Never Login
	then
		if [[ $createdAge -ge $days ]] # Created $days back
		then
                	if [[ ! -n $accessKeyIds ]] # Do not have access keys
                	then
				printf '%-20s %-15s %-15s %-15s %-50s \n' $username $createdAge "NA" "NA" "user never logged into console and do not have access keys and created $createdAge back"
                        else # User Do Have access keys
 				CheckAccesskeysAge "$accessKeyIds"
                                if [[ $finalAccessKeyAge == 9999 ]] # User Never Used Access Keys
				then
					printf '%-20s %-15s %-15s %-15s %-50s \n' $username $createdAge "NA" "NA" "User never logged into console and have access keys but access keys never used"
                                elif [[ $finalAccessKeyAge -ge $days ]] # User Dint Use Access Keys for $ days
                                then
					printf '%-20s %-15s %-15s %-15s %-50s \n' $username $createdAge "NA" $finalAccessKeyAge "User never logged into console and dint use access keys for $finalAccessKeyAge days"
                                fi
			fi
		fi
	fi

	if [[ "$lastLogin" != null ]] # User Logged in atleast once
	then
		loginAge=$(( ($(date +%s) - $(date --date=$lastLogin +%s)) / 86400 ))
		if [[ $loginAge -ge $days ]] # User Dint Login for $ days
		then
			if [[ ! -n $accessKeyIds ]]  # User Do not have Access Keys
			then
				printf '%-20s %-15s %-15s %-15s %-50s \n' $username $createdAge $loginAge "NA" "User dint login to console for $days and do not have access keys"
			else # User Do have Access Kes
				CheckAccesskeysAge "$accessKeyIds"
				if [[ $finalAccessKeyAge == 9999 ]]  # User Never Used Access Keys
				then
					printf '%-20s %-15s %-15s %-15s %-50s \n' $username $createdAge $loginAge "NA" "User dint login to console for $days and have access keys but access keys never used"
				elif [[ $finalAccessKeyAge -ge $days ]] # User Dint Use Access Keys for $ days 
                                then
					printf '%-20s %-15s %-15s %-15s %-50s \n' $username $createdAge $loginAge  $finalAccessKeyAge  "User dint login to console for $days and dint use access keys for $finalAccessKeyAge days"
                                fi
			fi
		fi
	fi
    done
}


################################################################################
##The list of all the roles used in the last x amount of days
################################################################################

function IAMRoles(){
        Last_Used_Date=$( aws iam get-role --role-name "$role" --profile "$profile" --output json |jq '.Role | .RoleLastUsed |select(.LastUsedDate != null) | .LastUsedDate'| tr -d '"')
        Role_Id=$(aws iam get-role --role-name "$role"  --profile "$profile"  --output json |jq '.Role.RoleId'| tr -d '"')
        CREATED_ON=$(aws iam get-role --role-name "$role"  --profile "$profile" --output json |jq '.Role | .CreateDate' | tr -d '"')
for dates in $Last_Used_Date;
do
            d1=$(date -jf %Y-%m-%d "$Today" +%s 2> /dev/null)
            d2=$(date -jf %Y-%m-%d "$dates" +%s 2> /dev/null)
            roleusedtimeinsec=`expr $d1 - $d2`
            age=`expr $roleusedtimeinsec / 86400`
return $age
done
}
CallIAMRoles(){
    printf "The List of the IAM Roles that haven't been used in the last $days days.\n"
    for role in $(aws iam list-roles --profile "$profile" --output json|jq -r '.Roles[]| .RoleName');
    do
        IAMRoles "$role"
    # This prints list of the roles that have not been used in the 30 days
    if [[ -n "$Role_Id" && $age -ge $days ]]; then
    printf "\nRole: $role  \n"
    printf "Last Used: $Last_Used_Date \t Created on: $CREATED_ON\n"
    fi
    done
}

##################################################################
# Flags to use Functions
##################################################################

while getopts :h,p:,u:,k:,r: option; do
   case $option in
   h|--help) # display Help
         Help
         exit;;
      p) # enter AWS profile name
         profile=${OPTARG};;
      u) # display List of IAM users who haven't logged in a given time
         days=${OPTARG}
         CallIAMUsers
         ;;
      r) #display list of roles that haven't been used in a give time
         days=${OPTARG}
         CallIAMRoles;;
     \?) # incorrect option
         echo "Error: Invalid option, Enter -help or -h for more details"
         exit;;
   esac
done
